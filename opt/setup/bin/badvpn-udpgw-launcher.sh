#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# DLGST XRAY PANEL
# BadVPN UDPGW Launcher
# ==========================================

CONFIG="/etc/default/badvpn-udpgw"
BINARY="/usr/local/bin/badvpn-udpgw"

# Default configuration
BADVPN_UDPGW_PORTS="${BADVPN_UDPGW_PORTS:-7300 7400 7500 7600 7700 7800 7900}"
BADVPN_UDPGW_MAX_CLIENTS="${BADVPN_UDPGW_MAX_CLIENTS:-512}"
BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT="${BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT:-8}"

# Load configuration
if [[ -f "$CONFIG" ]]; then
    source "$CONFIG"
fi

# Check binary
if [[ ! -x "$BINARY" ]]; then
    echo "[ERROR] BadVPN binary tidak ditemukan atau tidak executable."
    exit 1
fi

# Validate ports
for PORT in $BADVPN_UDPGW_PORTS; do
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
        echo "[ERROR] Port tidak valid: $PORT"
        exit 1
    fi
done

# Cleanup child processes
cleanup() {
    echo "[INFO] Menghentikan BadVPN UDPGW..."
    jobs -pr | xargs -r kill
    wait || true
}

trap cleanup EXIT INT TERM

echo "=========================================="
echo "       DLGST BADVPN UDPGW LAUNCHER"
echo "=========================================="
echo "[INFO] Binary       : $BINARY"
echo "[INFO] Ports        : $BADVPN_UDPGW_PORTS"
echo "[INFO] Max Clients  : $BADVPN_UDPGW_MAX_CLIENTS"
echo "[INFO] Max Conn     : $BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT"
echo "=========================================="

# Start UDPGW on each port
for PORT in $BADVPN_UDPGW_PORTS; do
    echo "[START] UDPGW port $PORT"

    "$BINARY" \
        --listen-addr "0.0.0.0:$PORT" \
        --max-clients "$BADVPN_UDPGW_MAX_CLIENTS" \
        --max-connections-for-client "$BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT" &

done

echo "[INFO] Semua proses UDPGW telah dijalankan."

# Keep launcher alive
wait