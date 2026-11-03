#!/usr/bin/env bash
# DLGST XRAY PANEL - Shadowsocks Users
# shellcheck shell=bash

SS_PANEL_BIN="${SS_PANEL_BIN:-/usr/local/lib/dlgst-shadowsocks/ssmanager.py}"
SS_HOST="${DLGST_SS_HOST:-}"

if [[ -z "$SS_HOST" && -s /etc/xray/domain ]]; then
    SS_HOST="$(head -n1 /etc/xray/domain | tr -d '[:space:]')"
fi

if [[ -z "$SS_HOST" ]] && declare -F detect_domain >/dev/null 2>&1; then
    SS_HOST="$(detect_domain)"
fi

if [[ -z "$SS_HOST" ]]; then
    SS_HOST="$(hostname -f 2>/dev/null || hostname)"
fi

dlgst_ss_action() {
    local label="$1"
    shift

    ui_menu_screen_begin "$label"
    hr

    if python3 "$SS_PANEL_BIN" "$@"; then
        :
    else
        warn "Operasi Shadowsocks gagal."
    fi

    hr
    read -r -p "Tekan ENTER untuk kembali..." _ || true
}

ss_select_account() {
    local title="$1"
    local name port expiry status
    local idx choice
    local -a names=() ports=() expiries=() statuses=()

    while IFS=$'\t' read -r name port expiry status; do
        [[ -n "$name" ]] || continue
        names+=("$name")
        ports+=("$port")
        expiries+=("$expiry")
        statuses+=("$status")
    done < <(
        python3 - <<'PYDATA'
import json
from pathlib import Path

root = Path("/opt/account/shadowsocks")

for p in sorted(root.glob("*.json")):
    try:
        a = json.loads(p.read_text())
        if not isinstance(a, dict):
            continue
        if a.get("status") == "deleted":
            continue

        expiry = str(a.get("expires_at", "-"))
        try:
            from datetime import datetime
            expiry = datetime.fromisoformat(
                expiry.replace("Z", "+00:00")
            ).strftime("%d-%m-%Y")
        except Exception:
            pass

        print(
            str(a.get("username", p.stem)) + "\t" +
            str(a.get("port", "-")) + "\t" +
            expiry + "\t" +
            str(a.get("status", "-"))
        )
    except Exception:
        continue
PYDATA
    )

    ui_menu_screen_begin "$title"

    printf "%-4s %-18s %-10s %-22s %-10s\n" \
        "NO" "USERNAME" "PORT" "EXPIRY" "STATUS"
    hr

    if ((${#names[@]} == 0)); then
        echo "Belum ada akun Shadowsocks."
        hr
        read -r -p "Tekan ENTER untuk kembali..." _ || true
        return 1
    fi

    for ((idx=0; idx<${#names[@]}; idx++)); do
        printf "%-4s %-18s %-10s %-22s %-10s\n" \
            "$((idx+1))" \
            "${names[idx]}" \
            "${ports[idx]}" \
            "${expiries[idx]}" \
            "${statuses[idx]}"
    done

    hr
    read -r -p "Pilih nomor akun (0 batal): " choice || return 1

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        warn "Masukkan nomor yang valid."
        sleep 1
        return 1
    }

    ((choice == 0)) && return 1

    if ((choice < 1 || choice > ${#names[@]})); then
        warn "Nomor akun tidak ditemukan."
        sleep 1
        return 1
    fi

    SS_SELECTED_USER="${names[$((choice-1))]}"
    return 0
}

shadowsocks_users_menu() {
    local c u d confirm

    local -a items=(
        "1|Add User"
        "2|Delete User"
        "3|Set Expiry"
        "4|Reset Password"
        "5|List Users"
        "0|Back to Main Menu"
    )

    while true; do
        ui_menu_screen_begin "4) DLGST Shadowsocks Users"
        ui_menu_render_options items 76
        hr

        if ! read -r -p "Pilih: " c; then
            return
        fi

        case "$c" in
            1)
                read -r -p "Username: " u || continue
                read -r -p "Masa aktif (hari): " d || continue

                [[ -n "$u" && "$d" =~ ^[0-9]+$ && "$d" -gt 0 ]] || {
                    warn "Username atau masa aktif tidak valid."
                    sleep 1
                    continue
                }

                dlgst_ss_action \
                    "Create Shadowsocks Account" \
                    add "$u" "$d" --host "$SS_HOST"
                ;;

            2)
                if ! ss_select_account "Delete Shadowsocks Account"; then
                    continue
                fi

                u="$SS_SELECTED_USER"
                read -r -p "Hapus akun $u? (y/n): " confirm || continue

                case "$confirm" in
                    y|Y)
                        dlgst_ss_action \
                            "Delete Shadowsocks Account" \
                            delete "$u"
                        ;;
                    *)
                        echo "Penghapusan dibatalkan."
                        sleep 1
                        ;;
                esac
                ;;

            3)
                if ! ss_select_account "Set Shadowsocks Expiry"; then
                    continue
                fi

                u="$SS_SELECTED_USER"

                echo
                echo "Akun terpilih: $u"
                read -r -p "Tambahan masa aktif (hari): " d || continue

                [[ "$d" =~ ^[0-9]+$ && "$d" -gt 0 ]] || {
                    warn "Jumlah hari tidak valid."
                    sleep 1
                    continue
                }

                dlgst_ss_action \
                    "Renew Shadowsocks Account" \
                    renew "$u" "$d"
                ;;

            4)
                if ! ss_select_account "Reset Shadowsocks Password"; then
                    continue
                fi

                u="$SS_SELECTED_USER"

                echo
                echo "Akun terpilih: $u"
                read -r -p "Reset password akun ini? (y/n): " confirm || continue

                case "$confirm" in
                    y|Y)
                        dlgst_ss_action \
                            "Reset Shadowsocks Password" \
                            reset "$u" --host "$SS_HOST"
                        ;;
                    *)
                        echo "Reset password dibatalkan."
                        sleep 1
                        ;;
                esac
                ;;

            5)
                dlgst_ss_action \
                    "Shadowsocks Account List" \
                    list
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
