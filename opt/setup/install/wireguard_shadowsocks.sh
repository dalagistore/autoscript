#!/usr/bin/env bash
# Independent provisioning for DLGST WireGuard and Shadowsocks.
# Each component is attempted even if the other one fails.

install_wireguard_component() {
    local endpoint iface port subnet server_addr

    log "Menyiapkan DLGST WireGuard..."
    [[ -s "${SETUP_BIN_SRC_DIR}/dlgst-wgpanel.py" ]] || die "Backend WireGuard tidak ditemukan."
    [[ -s "${SETUP_BIN_SRC_DIR}/dlgst-wg-firewall" ]] || die "Firewall WireGuard tidak ditemukan."
    [[ -s "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-wireguard-expire.service" ]] || die "Unit WireGuard expiry tidak ditemukan."
    [[ -s "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-wireguard-expire.timer" ]] || die "Timer WireGuard expiry tidak ditemukan."

    endpoint="${DOMAIN:-}"
    if [[ -z "${endpoint}" ]]; then
        endpoint="$(detect_domain)"
    fi
    [[ -n "${endpoint}" ]] || die "Domain endpoint WireGuard tidak ditemukan."

    iface="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [[ -n "${iface}" ]] || die "Tidak dapat mendeteksi interface jaringan utama."

    port="${DLGST_WG_PORT:-51820}"
    subnet="${DLGST_WG_SUBNET:-10.66.66.0/24}"
    server_addr="${DLGST_WG_SERVER_ADDR:-10.66.66.1/24}"

    python3 - "${endpoint}" "${port}" "${subnet}" "${server_addr}" "${iface}" <<'PY' || die "Validasi konfigurasi WireGuard gagal."
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
    if not labels or any(not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label) for label in labels):
        raise SystemExit("Endpoint WireGuard tidak valid.")

try:
    port = int(port)
except ValueError:
    raise SystemExit("Port WireGuard harus angka.")
if not 1 <= port <= 65535:
    raise SystemExit("Port WireGuard harus 1-65535.")
network = ipaddress.ip_network(subnet, strict=True)
server_ip = ipaddress.ip_interface(server_addr)
if server_ip.ip not in network:
    raise SystemExit("Alamat server WireGuard tidak berada dalam subnet.")
if server_ip.network.prefixlen != network.prefixlen:
    raise SystemExit("Prefix server address harus sama dengan subnet WireGuard.")
if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", iface):
    raise SystemExit("Interface jaringan tidak valid.")

state = "/var/lib/dlgst-wireguard"
os.makedirs(state, mode=0o700, exist_ok=True)
os.chmod(state, 0o700)
data = {
    "endpoint": endpoint,
    "port": port,
    "subnet": str(network),
    "server_addr": str(server_ip),
    "out_iface": iface,
}
fd, temporary = tempfile.mkstemp(prefix=".settings-", dir=state)
try:
    with os.fdopen(fd, "w") as file:
        json.dump(data, file, indent=2)
        file.write("\n")
        file.flush()
        os.fsync(file.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, os.path.join(state, "settings.json"))
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print("WireGuard settings berhasil dibuat.")
PY

    install -d -o root -g root -m 0750 /usr/local/lib/dlgst-wireguard /opt/account/wireguard /etc/wireguard || die "Gagal membuat direktori WireGuard."
    install -d -o root -g root -m 0700 /var/lib/dlgst-wireguard || die "Gagal membuat direktori state WireGuard."
    install -o root -g root -m 0750 "${SETUP_BIN_SRC_DIR}/dlgst-wgpanel.py" /usr/local/lib/dlgst-wireguard/wgpanel.py || die "Gagal memasang backend WireGuard."
    install -o root -g root -m 0750 "${SETUP_BIN_SRC_DIR}/dlgst-wg-firewall" /usr/local/sbin/dlgst-wg-firewall || die "Gagal memasang firewall WireGuard."
    install -o root -g root -m 0644 "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-wireguard-expire.service" /etc/systemd/system/dlgst-wireguard-expire.service || die "Gagal memasang unit WireGuard expiry."
    install -o root -g root -m 0644 "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-wireguard-expire.timer" /etc/systemd/system/dlgst-wireguard-expire.timer || die "Gagal memasang timer WireGuard expiry."

    cat > /etc/sysctl.d/99-dlgst-wireguard.conf <<'SYSCTL'
net.ipv4.ip_forward=1
SYSCTL
    sysctl -w net.ipv4.ip_forward=1 >/dev/null || die "Gagal mengaktifkan IPv4 forwarding."
    systemctl daemon-reload || die "Gagal reload systemd setelah instalasi WireGuard."
    /usr/local/lib/dlgst-wireguard/wgpanel.py expire || die "Gagal menginisialisasi WireGuard wg0."
    systemctl enable --now dlgst-wireguard-expire.timer || die "Gagal mengaktifkan WireGuard expiry timer."
    systemctl is-active --quiet wg-quick@wg0 || die "WireGuard wg0 tidak aktif."
    systemctl is-active --quiet dlgst-wireguard-expire.timer || die "WireGuard expiry timer tidak aktif."
    ok "DLGST WireGuard berhasil diintegrasikan."
}

install_shadowsocks_component() {
    log "Menyiapkan DLGST Shadowsocks..."
    [[ -s "${SETUP_BIN_SRC_DIR}/dlgst-ssmanager.py" ]] || die "Backend Shadowsocks tidak ditemukan."
    [[ -x /usr/bin/ss-server ]] || die "Binary ss-server tidak ditemukan; paket shadowsocks-libev belum siap."
    [[ -s "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss@.service" ]] || die "Template service Shadowsocks tidak ditemukan."
    [[ -s "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss-expire.service" ]] || die "Unit Shadowsocks expiry tidak ditemukan."
    [[ -s "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss-expire.timer" ]] || die "Timer Shadowsocks expiry tidak ditemukan."

    install -d -o root -g root -m 0750 /usr/local/lib/dlgst-shadowsocks /opt/account/shadowsocks || die "Gagal membuat direktori Shadowsocks."
    install -d -o root -g root -m 0750 /etc/dlgst-shadowsocks || die "Gagal membuat direktori konfigurasi Shadowsocks."
    install -o root -g root -m 0750 "${SETUP_BIN_SRC_DIR}/dlgst-ssmanager.py" /usr/local/lib/dlgst-shadowsocks/ssmanager.py || die "Gagal memasang backend Shadowsocks."
    install -o root -g root -m 0644 "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss@.service" /etc/systemd/system/dlgst-ss@.service || die "Gagal memasang template service Shadowsocks."
    install -o root -g root -m 0644 "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss-expire.service" /etc/systemd/system/dlgst-ss-expire.service || die "Gagal memasang unit Shadowsocks expiry."
    install -o root -g root -m 0644 "${SETUP_TEMPLATE_SRC_DIR}/systemd/dlgst-ss-expire.timer" /etc/systemd/system/dlgst-ss-expire.timer || die "Gagal memasang timer Shadowsocks expiry."

    systemctl daemon-reload || die "Gagal reload systemd setelah instalasi Shadowsocks."
    systemctl enable --now dlgst-ss-expire.timer || die "Gagal mengaktifkan Shadowsocks expiry timer."
    systemctl is-active --quiet dlgst-ss-expire.timer || die "Shadowsocks expiry timer tidak aktif."
    ok "DLGST Shadowsocks berhasil diintegrasikan."
}

install_wireguard_shadowsocks() {
    local wg_rc=0 ss_rc=0

    # Run in separate subshells: one component's failure must not skip the other.
    if ( install_wireguard_component ); then
        :
    else
        wg_rc=$?
        warn "Instalasi WireGuard gagal (exit ${wg_rc}); Shadowsocks tetap akan diproses."
    fi

    if ( install_shadowsocks_component ); then
        :
    else
        ss_rc=$?
        warn "Instalasi Shadowsocks gagal (exit ${ss_rc})."
    fi

    if (( wg_rc != 0 || ss_rc != 0 )); then
        die "Integrasi VPN belum lengkap. WireGuard exit=${wg_rc}; Shadowsocks exit=${ss_rc}. Periksa log setup."
    fi
}
