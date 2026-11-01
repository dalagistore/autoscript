#!/usr/bin/env bash

install_wireguard_shadowsocks() {
    local endpoint iface port subnet server_addr

    log "Menyiapkan DLGST WireGuard dan Shadowsocks..."

    # Validasi backend
    [[ -s "${SETUP_BIN_SRC_DIR}/dlgst-wgpanel.py" ]] \
        || die "Backend WireGuard tidak ditemukan."

    [[ -s "${SETUP_BIN_SRC_DIR}/dlgst-wg-firewall" ]] \
        || die "Firewall WireGuard tidak ditemukan."

    [[ -s "${SETUP_BIN_SRC_DIR}/dlgst-ssmanager.py" ]] \
        || die "Backend Shadowsocks tidak ditemukan."

    # Domain VPS baru
    endpoint="${DOMAIN:-}"
    if [[ -z "${endpoint}" ]]; then
        endpoint="$(detect_domain)"
    fi

    [[ -n "${endpoint}" ]] \
        || die "Domain endpoint WireGuard tidak ditemukan."

    # Interface utama VPS
    iface="$(ip -4 route get 1.1.1.1 2>/dev/null |
        awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"

    [[ -n "${iface}" ]] \
        || die "Tidak dapat mendeteksi interface jaringan utama."

    # Konfigurasi default, dapat dioverride melalui environment.
    port="${DLGST_WG_PORT:-51820}"
    subnet="${DLGST_WG_SUBNET:-10.66.66.0/24}"
    server_addr="${DLGST_WG_SERVER_ADDR:-10.66.66.1/24}"

    # Validasi konfigurasi dan tulis settings.json.
    python3 - "${endpoint}" "${port}" "${subnet}" \
        "${server_addr}" "${iface}" <<'PY'
import ipaddress
import json
import os
import re
import sys
import tempfile

endpoint, port, subnet, server_addr, iface = sys.argv[1:]

try:
    ipaddress.ip_address(endpoint)
except ValueError:
    if len(endpoint) > 253:
        raise SystemExit("Endpoint WireGuard terlalu panjang.")

    labels = endpoint.rstrip(".").split(".")
    if not labels or any(
        not re.fullmatch(
            r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?',
            label
        )
        for label in labels
    ):
        raise SystemExit("Endpoint WireGuard tidak valid.")

port = int(port)
if not 1 <= port <= 65535:
    raise SystemExit("Port WireGuard harus 1-65535.")

network = ipaddress.ip_network(subnet, strict=True)
server_ip = ipaddress.ip_interface(server_addr)

if server_ip.ip not in network:
    raise SystemExit("Alamat server WireGuard tidak berada dalam subnet.")

if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,64}', iface):
    raise SystemExit("Interface jaringan tidak valid.")

state = "/var/lib/dlgst-wireguard"
os.makedirs(state, mode=0o700, exist_ok=True)
os.chmod(state, 0o700)

data = {
    "endpoint": endpoint,
    "port": port,
    "subnet": str(network),
    "server_addr": str(server_ip),
    "out_iface": iface
}

fd, tmp = tempfile.mkstemp(prefix=".settings-", dir=state)

try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())

    os.chmod(tmp, 0o600)
    os.replace(tmp, os.path.join(state, "settings.json"))
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)

print("WireGuard settings berhasil dibuat.")
print("Endpoint :", endpoint)
print("Port     :", port)
print("Subnet   :", network)
print("Interface:", iface)
PY

    # Direktori runtime kosong untuk VPS baru
    install -d -o root -g root -m 0750 \
        /usr/local/lib/dlgst-wireguard \
        /usr/local/lib/dlgst-shadowsocks

    install -d -o root -g root -m 0700 \
        /var/lib/dlgst-wireguard

    install -d -o root -g root -m 0750 \
        /opt/account/wireguard \
        /opt/account/shadowsocks \
        /etc/dlgst-shadowsocks \
        /etc/wireguard

    # Install backend WireGuard
    install -o root -g root -m 0750 \
        "${SETUP_BIN_SRC_DIR}/dlgst-wgpanel.py" \
        /usr/local/lib/dlgst-wireguard/wgpanel.py

    install -o root -g root -m 0750 \
        "${SETUP_BIN_SRC_DIR}/dlgst-wg-firewall" \
        /usr/local/sbin/dlgst-wg-firewall

    # Install backend Shadowsocks
    install -o root -g root -m 0750 \
        "${SETUP_BIN_SRC_DIR}/dlgst-ssmanager.py" \
        /usr/local/lib/dlgst-shadowsocks/ssmanager.py

    # Install systemd templates
    install -o root -g root -m 0644 \
        "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-wireguard-expire.service" \
        /etc/systemd/system/dlgst-wireguard-expire.service

    install -o root -g root -m 0644 \
        "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-wireguard-expire.timer" \
        /etc/systemd/system/dlgst-wireguard-expire.timer

    install -o root -g root -m 0644 \
        "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss@.service" \
        /etc/systemd/system/dlgst-ss@.service

    install -o root -g root -m 0644 \
        "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss-expire.service" \
        /etc/systemd/system/dlgst-ss-expire.service

    install -o root -g root -m 0644 \
        "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss-expire.timer" \
        /etc/systemd/system/dlgst-ss-expire.timer

    # Aktifkan IPv4 forwarding untuk WireGuard
    cat > /etc/sysctl.d/99-dlgst-wireguard.conf <<'SYSCTL'
net.ipv4.ip_forward=1
SYSCTL

    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    # Reload systemd
    systemctl daemon-reload

    # Buat konfigurasi awal, private key baru, dan aktifkan wg0
    /usr/local/lib/dlgst-wireguard/wgpanel.py expire \
        || die "Gagal menginisialisasi WireGuard."

    # Aktifkan expiry checker
    systemctl enable --now dlgst-wireguard-expire.timer \
        || die "Gagal mengaktifkan WireGuard expiry timer."

    systemctl enable --now dlgst-ss-expire.timer \
        || die "Gagal mengaktifkan Shadowsocks expiry timer."

    # Validasi service dan timer
    systemctl is-active --quiet wg-quick@wg0 \
        || die "WireGuard wg0 tidak aktif."

    systemctl is-active --quiet dlgst-wireguard-expire.timer \
        || die "WireGuard expiry timer tidak aktif."

    systemctl is-active --quiet dlgst-ss-expire.timer \
        || die "Shadowsocks expiry timer tidak aktif."

    ok "DLGST WireGuard berhasil diintegrasikan."
    ok "DLGST Shadowsocks berhasil diintegrasikan."
}
