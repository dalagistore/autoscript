#!/usr/bin/env python3
"""DLGST Shadowsocks account manager.

All account operations are serialized through one process lock so expiry,
renewal, deletion and port allocation cannot race each other.
"""

import argparse
import base64
import contextlib
import datetime
import fcntl
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

DATA = Path("/opt/account/shadowsocks")
CONFIG = Path("/etc/dlgst-shadowsocks")
LOCK_FILE = Path("/run/lock/dlgst-shadowsocks.lock")
SERVICE = "dlgst-ss@{}.service"
METHOD = "chacha20-ietf-poly1305"
PORT_MIN = 20000
PORT_MAX = 40000


def ensure_paths():
    DATA.mkdir(parents=True, exist_ok=True)
    CONFIG.mkdir(parents=True, exist_ok=True)
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)


@contextlib.contextmanager
def manager_lock():
    ensure_paths()
    with LOCK_FILE.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def valid_username(username):
    if not re.fullmatch(r"[a-zA-Z0-9_-]{3,24}", username):
        raise ValueError("Username harus 3-24 karakter: huruf, angka, _ atau -.")
    return username


def account_path(username):
    return DATA / (valid_username(username) + ".json")


def config_path(username):
    return CONFIG / (valid_username(username) + ".json")


def run(command, check=True):
    return subprocess.run(
        command, check=check, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )


def atomic_json(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as file:
            json.dump(data, file, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_account(username):
    path = account_path(username)
    if not path.exists():
        raise ValueError("Akun tidak ditemukan.")
    account = json.loads(path.read_text())
    if not isinstance(account, dict):
        raise ValueError("Data akun tidak valid.")
    return account


def detect_host():
    result = subprocess.run(
        ["ip", "-4", "route", "get", "1.1.1.1"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    match = re.search(r"\bsrc\s+(\S+)", result.stdout)
    return match.group(1) if match else "IP-VPS"


def port_available(port):
    for sock_type in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
        sock = socket.socket(socket.AF_INET, sock_type)
        try:
            sock.bind(("0.0.0.0", port))
        except OSError:
            sock.close()
            return False
        sock.close()
    return True


def used_ports():
    ports = set()
    for path in DATA.glob("*.json"):
        try:
            account = json.loads(path.read_text())
            if account.get("status") in ("active", "pending", "expired"):
                ports.add(int(account["port"]))
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
            continue
    return ports


def allocate_port():
    used = used_ports()
    for port in range(PORT_MIN, PORT_MAX + 1):
        if port not in used and port_available(port):
            return port
    raise RuntimeError("Tidak tersedia port Shadowsocks.")


def create_service_config(account):
    config = {
        "server": "0.0.0.0",
        "server_port": int(account["port"]),
        "password": account["password"],
        "method": METHOD,
        "timeout": 300,
    }
    atomic_json(config_path(account["username"]), config, 0o640)


def service_action(username, action, check=True):
    result = run(["systemctl", action, SERVICE.format(valid_username(username))], check=False)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"Systemd gagal: {action} {username}")
    return result.returncode == 0


def make_url(account, host):
    raw = f'{METHOD}:{account["password"]}@{host}:{account["port"]}'
    encoded = base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")
    return "ss://" + encoded


def add(username, days, host):
    username = valid_username(username)
    days = int(days)
    if not 1 <= days <= 3650:
        raise ValueError("Masa aktif harus 1-3650 hari.")
    path = account_path(username)
    if path.exists():
        raise ValueError("Username sudah digunakan.")

    port = allocate_port()
    now = datetime.datetime.now(datetime.timezone.utc)
    expiry = now + datetime.timedelta(days=days)
    account = {
        "username": username,
        "port": port,
        "password": secrets.token_hex(16),
        "method": METHOD,
        "created_at": now.isoformat(),
        "expires_at": expiry.isoformat(),
        "status": "active",
    }

    atomic_json(path, account)
    try:
        create_service_config(account)
        run(["systemctl", "daemon-reload"])
        service_action(username, "enable")
        service_action(username, "start")
    except Exception:
        service_action(username, "disable", check=False)
        service_action(username, "stop", check=False)
        path.unlink(missing_ok=True)
        config_path(username).unlink(missing_ok=True)
        raise

    print("SHADOWSOCKS ACCOUNT CREATED")
    print("--------------------------------")
    print("Username :", username)
    print("Server   :", host)
    print("Port     :", port)
    print("Password :", account["password"])
    print("Method   :", METHOD)
    print("Expiry   :", expiry.strftime("%d-%m-%Y"))
    print("Protocol : TCP + UDP")
    print("Service  :", SERVICE.format(username))
    print("SS URL   :", make_url(account, host))


def delete(username):
    username = valid_username(username)
    account = load_account(username)
    service_action(username, "stop")
    service_action(username, "disable")
    account_path(username).unlink(missing_ok=True)
    config_path(username).unlink(missing_ok=True)
    print("Akun berhasil dihapus:", username)
    print("Port dibebaskan:", account.get("port", "-"))


def renew(username, days):
    """Renew active OR expired accounts and ensure their service is enabled."""
    username = valid_username(username)
    days = int(days)
    if not 1 <= days <= 3650:
        raise ValueError("Tambahan hari harus 1-3650.")

    account = load_account(username)
    if account.get("status") not in ("active", "expired"):
        raise ValueError("Status akun tidak dapat diperpanjang.")

    old_account = dict(account)
    old_expiry = datetime.datetime.fromisoformat(account["expires_at"])
    now = datetime.datetime.now(datetime.timezone.utc)
    if old_expiry.tzinfo is None:
        old_expiry = old_expiry.replace(tzinfo=datetime.timezone.utc)
    expiry = max(old_expiry, now) + datetime.timedelta(days=days)
    account["expires_at"] = expiry.isoformat()
    account["status"] = "active"
    account.pop("expired_at", None)

    atomic_json(account_path(username), account)
    try:
        create_service_config(account)
        run(["systemctl", "daemon-reload"])
        service_action(username, "enable")
        service_action(username, "start")
    except Exception:
        if old_account.get("status") == "active":
            atomic_json(account_path(username), old_account)
            create_service_config(old_account)
            service_action(username, "enable", check=False)
            service_action(username, "start", check=False)
        else:
            service_action(username, "stop", check=False)
            service_action(username, "disable", check=False)
            atomic_json(account_path(username), old_account)
            create_service_config(old_account)
        raise

    print("Akun diperpanjang:", username)
    print("Expiry baru:", expiry.strftime("%d-%m-%Y"))


def reset(username, host):
    username = valid_username(username)
    account = load_account(username)
    if account.get("status") != "active":
        raise ValueError("Akun tidak aktif.")

    old_account = dict(account)
    account["password"] = secrets.token_hex(16)
    atomic_json(account_path(username), account)
    try:
        create_service_config(account)
        service_action(username, "restart")
    except Exception:
        atomic_json(account_path(username), old_account)
        create_service_config(old_account)
        service_action(username, "restart", check=False)
        raise

    print("Password berhasil direset.")
    print("Username :", username)
    print("Server   :", host)
    print("Port     :", account["port"])
    print("Password :", account["password"])
    print("Method   :", METHOD)
    print("SS URL   :", make_url(account, host))


def list_accounts():
    print(f'{"USERNAME":<20} {"PORT":<8} {"EXPIRY":<28} {"STATUS"}')
    print("-" * 75)
    for path in sorted(DATA.glob("*.json")):
        try:
            account = json.loads(path.read_text())
            print(
                f'{account["username"]:<20} {account["port"]:<8} '
                f'{account["expires_at"][:19]:<28} {account["status"]}'
            )
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
            print("Data rusak:", path.name)


def expire():
    now = datetime.datetime.now(datetime.timezone.utc)
    failures = 0
    for path in sorted(DATA.glob("*.json")):
        try:
            account = json.loads(path.read_text())
            if not isinstance(account, dict) or account.get("status") != "active":
                continue
            expiry = datetime.datetime.fromisoformat(account["expires_at"])
            if expiry.tzinfo is None:
                expiry = expiry.replace(tzinfo=datetime.timezone.utc)
            if expiry <= now:
                username = valid_username(account["username"])
                # Mark expired only after the service has actually been stopped.
                service_action(username, "stop")
                service_action(username, "disable")
                account["status"] = "expired"
                account["expired_at"] = now.isoformat()
                atomic_json(path, account)
                print("Expired:", username)
        except Exception as error:
            failures += 1
            print("Gagal memproses", path.name, ":", error, file=sys.stderr)
    if failures:
        raise RuntimeError(f"Expiry checker gagal memproses {failures} akun; periksa log.")


def main():
    parser = argparse.ArgumentParser(description="DLGST Shadowsocks Manager")
    sub = parser.add_subparsers(dest="action", required=True)

    p = sub.add_parser("add")
    p.add_argument("username")
    p.add_argument("days", type=int)
    p.add_argument("--host", default=detect_host())

    p = sub.add_parser("delete")
    p.add_argument("username")

    p = sub.add_parser("renew")
    p.add_argument("username")
    p.add_argument("days", type=int)

    p = sub.add_parser("reset")
    p.add_argument("username")
    p.add_argument("--host", default=detect_host())

    sub.add_parser("list")
    sub.add_parser("expire")
    args = parser.parse_args()

    try:
        with manager_lock():
            if args.action == "add":
                add(args.username, args.days, args.host)
            elif args.action == "delete":
                delete(args.username)
            elif args.action == "renew":
                renew(args.username, args.days)
            elif args.action == "reset":
                reset(args.username, args.host)
            elif args.action == "list":
                list_accounts()
            elif args.action == "expire":
                expire()
    except Exception as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
