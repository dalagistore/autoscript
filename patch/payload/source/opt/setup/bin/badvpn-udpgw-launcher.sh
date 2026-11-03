#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# DLGST XRAY PANEL
# BadVPN UDPGW Launcher
# ==========================================

BADVPN_BIN="${1:-/usr/local/bin/badvpn-udpgw}"
RUNTIME_ENV_FILE="${2:-/etc/default/badvpn-udpgw}"

if [[ ! -x "$BADVPN_BIN" ]]; then
    echo "[ERROR] Binary BadVPN tidak ditemukan: $BADVPN_BIN" >&2
    exit 1
fi

# Default configuration
BADVPN_UDPGW_PORTS="7300 7400 7500 7600 7700 7800 7900"
BADVPN_UDPGW_MAX_CLIENTS=512
BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT=8

# Load runtime configuration
if [[ -f "$RUNTIME_ENV_FILE" ]]; then
    source "$RUNTIME_ENV_FILE"
fi

# Validate binary
"$BADVPN_BIN" --help >/dev/null 2>&1 || {
    echo "[ERROR] Binary BadVPN gagal dijalankan." >&2
    exit 1
}

PIDS=()

cleanup() {
    echo "[INFO] Stopping BadVPN UDPGW..."

    if ((${#PIDS[@]})); then
        kill "${PIDS[@]}" 2>/dev/null || true
        wait "${PIDS[@]}" 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'exit 0' INT TERM

echo "=========================================="
echo "       DLGST BADVPN UDPGW"
echo "=========================================="
echo "[INFO] Binary: $BADVPN_BIN"
echo "[INFO] Ports : $BADVPN_UDPGW_PORTS"
echo "[INFO] Clients: $BADVPN_UDPGW_MAX_CLIENTS"
echo "=========================================="

for PORT in $BADVPN_UDPGW_PORTS; do
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
        echo "[ERROR] Invalid port: $PORT" >&2
        exit 1
    fi

    echo "[START] UDPGW port $PORT"

    "$BADVPN_BIN" \
        --listen-addr "0.0.0.0:$PORT" \
        --max-clients "$BADVPN_UDPGW_MAX_CLIENTS" \
        --max-connections-for-client "$BADVPN_UDPGW_MAX_CONNECTIONS_FOR_CLIENT" &

    PIDS+=("$!")
done

echo "[OK] BadVPN UDPGW processes started."

wait
