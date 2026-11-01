#!/usr/bin/env python3

import argparse
import base64
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
SERVICE = "dlgst-ss@{}.service"

METHOD = "chacha20-ietf-poly1305"
PORT_MIN = 20000
PORT_MAX = 40000

DATA.mkdir(parents=True, exist_ok=True)
CONFIG.mkdir(parents=True, exist_ok=True)


def valid_username(username):
    if not re.fullmatch(r"[a-zA-Z0-9_-]{3,24}", username):
        raise ValueError(
            "Username harus 3-24 karakter: huruf, angka, _ atau -."
        )
    return username


def account_path(username):
    return DATA / (valid_username(username) + ".json")


def config_path(username):
    return CONFIG / (valid_username(username) + ".json")


def run(command, check=True):
    return subprocess.run(
        command,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )


def atomic_json(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)

    fd, temporary = tempfile.mkstemp(
        prefix=".tmp-",
        dir=str(path.parent)
    )

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

    return json.loads(path.read_text())


def detect_host():
    result = subprocess.run(
        ["ip", "-4", "route", "get", "1.1.1.1"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL
    )

    match = re.search(r"\bsrc\s+(\S+)", result.stdout)

    if match:
        return match.group(1)

    return "IP-VPS"


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

            if account.get("status") == "active":
                ports.add(int(account["port"]))

        except Exception:
            continue

    return ports


def allocate_port():
    used = used_ports()

    for port in range(PORT_MIN, PORT_MAX + 1):
        if port in used:
            continue

        if port_available(port):
            return port

    raise RuntimeError("Tidak tersedia port Shadowsocks.")


def create_service_config(account):
    config = {
        "server": "0.0.0.0",
        "server_port": int(account["port"]),
        "password": account["password"],
        "method": METHOD,
        "timeout": 300
    }

    atomic_json(config_path(account["username"]), config, 0o640)


def service_action(username, action):
    result = run(
        ["systemctl", action, SERVICE.format(valid_username(username))],
        check=False
    )

    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip() or
            "Systemd gagal menjalankan operasi."
        )


def make_url(account, host):
    raw = (
        f'{METHOD}:{account["password"]}'
        f'@{host}:{account["port"]}'
    )

    encoded = base64.urlsafe_b64encode(
        raw.encode()
    ).decode().rstrip("=")

    return "ss://" + encoded


def add(username, days, host):
    username = valid_username(username)
    days = int(days)

    if days < 1 or days > 3650:
        raise ValueError("Masa aktif harus 1-3650 hari.")

    with open("/run/lock/dlgst-shadowsocks.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

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
            "status": "active"
        }

        atomic_json(path, account)
        create_service_config(account)

        try:
            run(["systemctl", "daemon-reload"])
            service_action(username, "enable")
            service_action(username, "start")

        except Exception:
            service_action(username, "disable")
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
    print("Port dibebaskan:", account["port"])


def renew(username, days):
    username = valid_username(username)
    days = int(days)

    if days < 1 or days > 3650:
        raise ValueError("Tambahan hari harus 1-3650.")

    account = load_account(username)

    if account.get("status") != "active":
        raise ValueError("Akun tidak aktif.")

    old_expiry = datetime.datetime.fromisoformat(
        account["expires_at"]
    )

    now = datetime.datetime.now(datetime.timezone.utc)
    base = max(old_expiry, now)

    expiry = base + datetime.timedelta(days=days)
    account["expires_at"] = expiry.isoformat()

    atomic_json(account_path(username), account)

    print("Akun diperpanjang:", username)
    print("Expiry baru:", expiry.strftime("%d-%m-%Y"))


def reset(username, host):
    username = valid_username(username)
    account = load_account(username)

    if account.get("status") != "active":
        raise ValueError("Akun tidak aktif.")

    account["password"] = secrets.token_hex(16)
    atomic_json(account_path(username), account)

    create_service_config(account)
    service_action(username, "restart")

    print("Password berhasil direset.")
    print("Username :", username)
    print("Server   :", host)
    print("Port     :", account["port"])
    print("Password :", account["password"])
    print("Method   :", METHOD)
    print("SS URL   :", make_url(account, host))


def list_accounts():
    print(
        f'{"USERNAME":<20} {"PORT":<8} '
        f'{"EXPIRY":<28} {"STATUS"}'
    )
    print("-" * 75)

    for path in sorted(DATA.glob("*.json")):
        try:
            account = json.loads(path.read_text())

            print(
                f'{account["username"]:<20} '
                f'{account["port"]:<8} '
                f'{account["expires_at"][:19]:<28} '
                f'{account["status"]}'
            )

        except Exception:
            print("Data rusak:", path.name)


def expire():
    now = datetime.datetime.now(datetime.timezone.utc)

    for path in sorted(DATA.glob("*.json")):
        try:
            account = json.loads(path.read_text())

            if account.get("status") != "active":
                continue

            expiry = datetime.datetime.fromisoformat(
                account["expires_at"]
            )

            if expiry.tzinfo is None:
                expiry = expiry.replace(
                    tzinfo=datetime.timezone.utc
                )

            if expiry <= now:
                username = valid_username(account["username"])

                service_action(username, "stop")
                service_action(username, "disable")

                account["status"] = "expired"
                account["expired_at"] = now.isoformat()

                atomic_json(path, account)

                print("Expired:", username)

        except Exception as error:
            print("Gagal memproses", path.name, ":", error)


def main():
    parser = argparse.ArgumentParser(
        description="DLGST Shadowsocks Manager"
    )

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
