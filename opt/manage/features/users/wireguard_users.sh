#!/usr/bin/env bash

WG_PANEL_BIN="${WG_PANEL_BIN:-/usr/local/lib/dlgst-wireguard/wgpanel.py}"

wg_load_users() {
    local include_deleted="${1:-0}"

    WG_NAMES=()
    WG_IPS=()
    WG_EXPIRIES=()
    WG_STATUSES=()

    while IFS=$'\t' read -r name ip expiry status; do
        [[ -n "$name" ]] || continue

        WG_NAMES+=("$name")
        WG_IPS+=("$ip")
        WG_EXPIRIES+=("$expiry")
        WG_STATUSES+=("$status")
    done < <(python3 - "$include_deleted" <<'PY'
import json
import sys
from pathlib import Path

root = Path("/opt/account/wireguard")
include_deleted = sys.argv[1] == "1"

for p in sorted(root.glob("*.json")):
    try:
        a = json.loads(p.read_text())
        if not isinstance(a, dict):
            continue

        status = str(a.get("status", "-"))

        if status == "deleted" and not include_deleted:
            continue

        print(
            str(a.get("username", p.stem)) + "\t" +
            str(a.get("address", "-")) + "\t" +
            str(a.get("expires_at", "-")) + "\t" +
            status
        )
    except Exception:
        continue
PY
)
}

wg_select_user() {
    local title="$1"
    local include_deleted="${2:-0}"
    local choice idx

    wg_load_users "$include_deleted"

    ui_menu_screen_begin "$title"

    printf "%-4s %-20s %-16s %-12s %-10s\n" \
        "NO" "USERNAME" "IP ADDRESS" "EXPIRY" "STATUS"

    hr

    if ((${#WG_NAMES[@]} == 0)); then
        echo "Belum ada akun WireGuard."
        hr
        read -r -p "Tekan ENTER..." _ || true
        return 1
    fi

    for ((idx=0; idx<${#WG_NAMES[@]}; idx++)); do
        printf "%-4s %-20s %-16s %-12s %-10s\n" \
            "$((idx+1))" \
            "${WG_NAMES[idx]}" \
            "${WG_IPS[idx]}" \
            "${WG_EXPIRIES[idx]}" \
            "${WG_STATUSES[idx]}"
    done

    hr

    read -r -p "Pilih nomor akun (0 batal): " choice || return 1

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Nomor tidak valid."
        sleep 1
        return 1
    }

    ((choice == 0)) && return 1

    if ((choice < 1 || choice > ${#WG_NAMES[@]})); then
        warn "Nomor akun tidak ditemukan."
        sleep 1
        return 1
    fi

    WG_SELECTED="${WG_NAMES[$((choice-1))]}"
    return 0
}

dlgst_wg_action() {
    local label="$1"
    shift

    ui_menu_screen_begin "$label"
    hr

    if "$WG_PANEL_BIN" "$@"; then
        echo
        echo "Operasi berhasil."
    else
        warn "Operasi WireGuard gagal."
    fi

    hr
    read -r -p "Tekan ENTER untuk kembali..." _ || true
}

wireguard_users_menu() {
    local c u d confirm

    local -a items=(
        "1|Add User"
        "2|Delete User"
        "3|Set Expiry"
        "4|Reset Private Key"
        "5|List Users"
        "0|Back to Main Menu"
    )

    while true; do
        ui_menu_screen_begin "3) DLGST WireGuard Users"
        ui_menu_render_options items 76
        hr

        if ! read -r -p "Pilih: " c; then
            return
        fi

        case "$c" in

            1)
                read -r -p "Username: " u || continue
                read -r -p "Masa aktif (hari): " d || continue

                dlgst_wg_action "Create WireGuard Account" add "$u" "$d"
                ;;

            2)
                if ! wg_select_user "Delete WireGuard Account"; then
                    continue
                fi

                u="$WG_SELECTED"

                read -r -p "Hapus akun $u? (y/n): " confirm || continue

                case "$confirm" in
                    y|Y)
                        dlgst_wg_action "Delete WireGuard Account" delete "$u"
                        ;;
                    *)
                        echo "Penghapusan dibatalkan."
                        sleep 1
                        ;;
                esac
                ;;

            3)
                if ! wg_select_user "Set WireGuard Expiry"; then
                    continue
                fi

                u="$WG_SELECTED"

                read -r -p "Tambahan masa aktif (hari): " d || continue

                dlgst_wg_action "Renew WireGuard Account" expiry "$u" "$d"
                ;;

            4)
                if ! wg_select_user "Reset WireGuard Private Key"; then
                    continue
                fi

                u="$WG_SELECTED"

                echo
                warn "Reset key akan mengganti konfigurasi client lama."
                read -r -p "Lanjutkan reset key $u? (y/n): " confirm || continue

                case "$confirm" in
                    y|Y)
                        dlgst_wg_action "Reset WireGuard Private Key" reset "$u"
                        ;;
                    *)
                        echo "Reset dibatalkan."
                        sleep 1
                        ;;
                esac
                ;;

            5)
                dlgst_wg_action "WireGuard Account List" list
                ;;

            0|b|back|kembali)
                return
                ;;

            *)
                warn "Pilihan tidak valid."
                sleep 1
                ;;
        esac
    done
}
