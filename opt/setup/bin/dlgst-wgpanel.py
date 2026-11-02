#!/usr/bin/env python3
"""DLGST WireGuard account manager with serialized, atomic state updates."""

import argparse
import datetime as dt
import fcntl
import ipaddress
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

CONF = pathlib.Path('/etc/wireguard/wg0.conf')
DATA = pathlib.Path('/opt/account/wireguard')
STATE = pathlib.Path('/var/lib/dlgst-wireguard')
SETTINGS = STATE / 'settings.json'
LOCK = STATE / 'lock'


def run(args, **kwargs):
    kwargs.setdefault('check', True)
    kwargs.setdefault('text', True)
    return subprocess.run(args, **kwargs)


def read(path, default=None):
    try:
        with path.open(encoding='utf-8') as file:
            return json.load(file)
    except FileNotFoundError:
        return default


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.tmp-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            json.dump(value, file, indent=2)
            file.write('\n')
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_text_atomic(path, value, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.tmp-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            file.write(value.rstrip('\n') + '\n')
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def cfg():
    settings = read(SETTINGS, {})
    if not isinstance(settings, dict) or not settings:
        raise RuntimeError('WireGuard settings.json belum tersedia atau tidak valid.')
    return settings


def users():
    result = []
    for path in DATA.glob('*.json'):
        account = read(path)
        if isinstance(account, dict):
            result.append(account)
    return result


def valid_name(username):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,32}', username):
        raise ValueError('Username 1-32 karakter: huruf, angka, _ atau -')


def keys():
    private = run(['wg', 'genkey'], stdout=subprocess.PIPE).stdout.strip()
    public = run(['wg', 'pubkey'], input=private + '\n', stdout=subprocess.PIPE).stdout.strip()
    if not private or not public:
        raise RuntimeError('Gagal membuat pasangan key WireGuard.')
    return private, public


def ensure_server_keys():
    private_path = STATE / 'server_private.key'
    public_path = STATE / 'server_public.key'
    if not private_path.exists():
        private, public = keys()
        write_text_atomic(private_path, private)
        write_text_atomic(public_path, public)
    elif not public_path.exists():
        private = private_path.read_text(encoding='utf-8').strip()
        public = run(['wg', 'pubkey'], input=private + '\n', stdout=subprocess.PIPE).stdout.strip()
        if not public:
            raise RuntimeError('Gagal membaca public key server WireGuard.')
        write_text_atomic(public_path, public)
    return private_path.read_text(encoding='utf-8').strip()


def server_public_key():
    ensure_server_keys()
    return (STATE / 'server_public.key').read_text(encoding='utf-8').strip()


def client_config(account):
    settings = cfg()
    return '\n'.join([
        '[Interface]',
        f"PrivateKey = {account['private_key']}",
        f"Address = {account['address']}/32",
        'DNS = 1.1.1.1, 1.0.0.1',
        '[Peer]',
        f'PublicKey = {server_public_key()}',
        'AllowedIPs = 0.0.0.0/0',
        f"Endpoint = {settings['endpoint']}:{settings['port']}",
        'PersistentKeepalive = 25',
        '',
    ])


def save_client(account):
    path = DATA / (account['username'] + '.conf')
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.client-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            file.write(client_config(account))
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def server_config():
    settings = cfg()
    server_private = ensure_server_keys()
    lines = [
        '[Interface]',
        f"Address = {settings['server_addr']}",
        f"ListenPort = {settings['port']}",
        f'PrivateKey = {server_private}',
        'SaveConfig = false',
        f"PostUp = /usr/local/sbin/dlgst-wg-firewall up {settings['subnet']} {settings['out_iface']}",
        'PostDown = /usr/local/sbin/dlgst-wg-firewall down',
        '',
    ]
    today = dt.date.today()
    for account in users():
        try:
            valid = account.get('status') == 'active' and dt.date.fromisoformat(account['expires_at']) >= today
            if valid:
                ipaddress.ip_address(account['address'])
                lines.extend([
                    '[Peer]',
                    f"# {account['username']}",
                    f"PublicKey = {account['public_key']}",
                    f"AllowedIPs = {account['address']}/32",
                    '',
                ])
        except (KeyError, TypeError, ValueError):
            continue

    CONF.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.wg0-', dir=str(CONF.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            file.write('\n'.join(lines))
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, CONF)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sync():
    server_config()
    exists = subprocess.run(
        ['ip', 'link', 'show', 'wg0'], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    ).returncode == 0
    if exists:
        settings = cfg()
        # wg-quick PostUp is not rerun by syncconf. Reconcile our dedicated
        # NAT table explicitly so installer reruns recover missing/stale rules.
        run(['/usr/local/sbin/dlgst-wg-firewall', 'up', settings['subnet'], settings['out_iface']])
        run(['bash', '-c', 'wg syncconf wg0 <(wg-quick strip wg0)'])
    else:
        run(['systemctl', 'enable', '--now', 'wg-quick@wg0'])


def expire(_=None):
    today = dt.date.today()
    changed = []
    for account in users():
        if account.get('status') != 'active':
            continue
        try:
            expired = dt.date.fromisoformat(account['expires_at']) < today
        except (KeyError, TypeError, ValueError):
            expired = True
        if expired:
            changed.append(dict(account))
            account['status'] = 'expired'
            write(DATA / (account['username'] + '.json'), account)
    try:
        sync()
    except Exception:
        for old in changed:
            write(DATA / (old['username'] + '.json'), old)
        try:
            sync()
        except Exception:
            pass
        raise


def add(args):
    username = args.username.strip()
    valid_name(username)
    path = DATA / (username + '.json')
    existing = read(path)
    if existing and existing.get('status') != 'deleted':
        raise ValueError('Username sudah ada')
    if not 1 <= args.days <= 3650:
        raise ValueError('Hari aktif 1-3650')

    settings = cfg()
    network = ipaddress.ip_network(settings['subnet'], strict=True)
    server_ip = ipaddress.ip_interface(settings['server_addr']).ip
    used = {a.get('address') for a in users() if a.get('status') in ('active', 'pending', 'expired')}
    address = next((str(ip) for ip in network.hosts() if ip != server_ip and str(ip) not in used), None)
    if not address:
        raise ValueError('Pool IP penuh')

    private, public = keys()
    today = dt.date.today()
    account = {
        'username': username,
        'address': address,
        'private_key': private,
        'public_key': public,
        'created_at': today.isoformat(),
        'expires_at': (today + dt.timedelta(days=args.days)).isoformat(),
        'status': 'pending',
    }
    write(path, account)
    try:
        save_client(account)
        account['status'] = 'active'
        write(path, account)
        sync()
    except Exception:
        account['status'] = 'deleted'
        write(path, account)
        (DATA / (username + '.conf')).unlink(missing_ok=True)
        try:
            sync()
        except Exception:
            pass
        raise

    print(f"User: {username}\nIP: {address}\nExpiry: {account['expires_at']}\nConfig: {DATA/(username+'.conf')}")
    config = client_config(account)
    print('\n========== WIREGUARD CONFIGURATION (TEXT) ==========')
    print(config)
    print('========== WIREGUARD QR CODE ==========')
    run(['qrencode', '-t', 'ANSIUTF8', '-o', '-'], check=False, input=config)


def delete(args):
    valid_name(args.username)
    path = DATA / (args.username + '.json')
    account = read(path)
    if not account:
        raise ValueError('User tidak ditemukan')
    old = dict(account)
    account['status'] = 'deleted'
    write(path, account)
    (DATA / (args.username + '.conf')).unlink(missing_ok=True)
    try:
        sync()
    except Exception:
        write(path, old)
        if old.get('status') == 'active':
            save_client(old)
        try:
            sync()
        except Exception:
            pass
        raise
    print('User dihapus')


def expiry(args):
    valid_name(args.username)
    path = DATA / (args.username + '.json')
    account = read(path)
    if not account or account.get('status') == 'deleted':
        raise ValueError('User tidak ditemukan')
    if not 1 <= args.days <= 3650:
        raise ValueError('Hari aktif 1-3650')
    old = dict(account)
    account['expires_at'] = (dt.date.today() + dt.timedelta(days=args.days)).isoformat()
    account['status'] = 'active'
    write(path, account)
    try:
        save_client(account)
        sync()
    except Exception:
        write(path, old)
        if old.get('status') == 'active':
            save_client(old)
        else:
            (DATA / (args.username + '.conf')).unlink(missing_ok=True)
        try:
            sync()
        except Exception:
            pass
        raise
    print(account['expires_at'])


def reset(args):
    valid_name(args.username)
    path = DATA / (args.username + '.json')
    account = read(path)
    if not account or account.get('status') != 'active':
        raise ValueError('User tidak ditemukan atau tidak aktif')
    if dt.date.fromisoformat(account['expires_at']) < dt.date.today():
        raise ValueError('Akun sudah expired; perpanjang masa aktif terlebih dahulu')

    old = dict(account)
    account['private_key'], account['public_key'] = keys()
    write(path, account)
    try:
        save_client(account)
        sync()
    except Exception:
        write(path, old)
        save_client(old)
        try:
            sync()
        except Exception:
            pass
        raise

    config = client_config(account)
    print('\n' + '=' * 60)
    print('          RESET WIREGUARD PRIVATE KEY')
    print('=' * 60)
    print(f"USERNAME : {account['username']}")
    print(f"IP       : {account['address']}")
    print(f"CREATED  : {account.get('created_at', '-')}")
    print(f"EXPIRY   : {account.get('expires_at', '-')}")
    print(f"STATUS   : {account['status'].upper()}")
    print(f"CONFIG   : {DATA/(args.username+'.conf')}")
    print('\n' + '=' * 60 + '\n       WIREGUARD CONFIGURATION (TEXT)\n' + '=' * 60)
    print(config)
    print('=' * 60 + '\n                  QR CODE\n' + '=' * 60)
    run(['qrencode', '-t', 'ANSIUTF8', '-o', '-'], check=False, input=config)


def listing(_args):
    expire()
    print(f"{'USERNAME':20} {'IP':16} {'EXPIRY':12} STATUS")
    for account in users():
        print(f"{account.get('username', '-')[:20]:20} {account.get('address', '-')[:16]:16} {account.get('expires_at', '-')[:12]:12} {account.get('status', '-')}")


def main():
    parser = argparse.ArgumentParser(description='DLGST WireGuard Manager')
    sub = parser.add_subparsers(dest='cmd', required=True)
    for command, handler, needs_days in (
        ('add', add, True), ('delete', delete, False),
        ('expiry', expiry, True), ('reset', reset, False),
        ('list', listing, False), ('expire', expire, False),
    ):
        item = sub.add_parser(command)
        if command in ('add', 'delete', 'expiry', 'reset'):
            item.add_argument('username')
        if needs_days:
            item.add_argument('days', type=int)
        item.set_defaults(handler=handler)

    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    with LOCK.open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        args.handler(args)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('ERROR:', error, file=sys.stderr)
        sys.exit(1)
