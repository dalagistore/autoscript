#!/bin/bash
set -Eeuo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$BASE/payload"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/DLGST-UPDATE-PATCH-FIX-BACKUP-$STAMP"

SOURCE="/opt/autoscript"
RUNTIME="/"

SUCCESS=0

echo "=========================================="
echo " DLGST XRAY PANEL UPDATE PATCH FIX V1"
echo "=========================================="

[ "$(id -u)" -eq 0 ] || {
    echo "ERROR: Jalankan sebagai root."
    exit 1
}

[ -d "$SOURCE/.git" ] || {
    echo "ERROR: Source /opt/autoscript tidak ditemukan."
    exit 1
}

[ -d "$PAYLOAD/source" ] && [ -d "$PAYLOAD/runtime" ] || {
    echo "ERROR: Payload tidak lengkap."
    exit 1
}

echo
echo "===== VALIDASI SHA256 ====="
cd "$BASE"
sha256sum -c SHA256SUMS

backup_tree() {
    local payload="$1"
    local target="$2"
    local backup="$3"

    mkdir -p "$backup/files"

    while IFS= read -r -d '' file; do
        local rel="${file#"$payload"/}"
        local dest="$target/$rel"

        mkdir -p "$backup/files/$(dirname "$rel")"

        if [ -e "$dest" ]; then
            cp -a "$dest" "$backup/files/$rel"
        else
            mkdir -p "$backup/missing/$(dirname "$rel")"
            touch "$backup/missing/$rel"
        fi
    done < <(find "$payload" -type f ! -path '*/web/dist/*' -print0)

    if [ -d "$payload/account-portal/web/dist" ]; then
        if [ -d "$target/account-portal/web/dist" ]; then
            mkdir -p "$backup/dist"
            cp -a "$target/account-portal/web/dist" "$backup/dist/"
            touch "$backup/dist-existed"
        fi
    fi
}

deploy_tree() {
    local payload="$1"
    local target="$2"

    while IFS= read -r -d '' file; do
        local rel="${file#"$payload"/}"
        local dest="$target/$rel"

        mkdir -p "$(dirname "$dest")"
        cp -a "$file" "$dest"
    done < <(find "$payload" -type f ! -path '*/web/dist/*' -print0)

    if [ -d "$payload/account-portal/web/dist" ]; then
        rm -rf "$target/account-portal/web/dist"
        mkdir -p "$target/account-portal/web"
        cp -a "$payload/account-portal/web/dist" \
              "$target/account-portal/web/dist"
    fi
}

restore_tree() {
    local payload="$1"
    local target="$2"
    local backup="$3"

    while IFS= read -r -d '' file; do
        local rel="${file#"$payload"/}"
        local dest="$target/$rel"

        rm -f "$dest"

        if [ -f "$backup/files/$rel" ]; then
            mkdir -p "$(dirname "$dest")"
            cp -a "$backup/files/$rel" "$dest"
        fi
    done < <(find "$payload" -type f ! -path '*/web/dist/*' -print0)

    if [ -d "$payload/account-portal/web/dist" ]; then
        rm -rf "$target/account-portal/web/dist"

        if [ -f "$backup/dist-existed" ]; then
            mkdir -p "$target/account-portal/web"
            cp -a "$backup/dist" "$target/account-portal/web/"
        fi
    fi
}

rollback() {
    local rc="${1:-1}"

    echo
    echo "===== ROLLBACK ====="

    set +e

    restore_tree "$PAYLOAD/runtime" "/" "$BACKUP/runtime"
    restore_tree "$PAYLOAD/source" "$SOURCE" "$BACKUP/source"

    echo "Rollback selesai."
    echo "Backup: $BACKUP"

    exit "$rc"
}

echo
echo "===== BACKUP SOURCE DAN RUNTIME ====="

mkdir -p "$BACKUP"

backup_tree "$PAYLOAD/source" "$SOURCE" "$BACKUP/source"
backup_tree "$PAYLOAD/runtime" "/" "$BACKUP/runtime"

echo "Backup: $BACKUP"

echo
echo "===== UPDATE SOURCE ====="

deploy_tree "$PAYLOAD/source" "$SOURCE"

echo
echo "===== UPDATE RUNTIME ====="

if [ -f "$PAYLOAD/runtime/opt/account-portal/app/data.py" ]; then
    [ -d /opt/account-portal ] || {
        echo "ERROR: Runtime Account Portal tidak ditemukan."
        rollback 1
    }
fi

deploy_tree "$PAYLOAD/runtime" "/"

echo
echo "===== PERMISSION ====="

chmod 755 \
    /opt/manage/features/users/ssh_qac.sh \
    /opt/manage/features/users/ssh_users.sh \
    /opt/manage/features/users/xray_qac.sh \
    /opt/manage/features/users/xray_users.sh \
    /usr/local/lib/autoscript-setup/opt/setup/bin/badvpn-udpgw-launcher.sh \
    /usr/local/lib/autoscript-setup/opt/setup/install/management.sh

echo
echo "===== VERIFIKASI PORTAL ====="

diff -qr \
    "$SOURCE/account-portal/web/dist" \
    /opt/account-portal/web/dist || rollback 1

echo
echo "===== VERIFIKASI RUNTIME ====="

for f in \
    /opt/account-portal/app/data.py \
    /opt/manage/features/users/ssh_qac.sh \
    /opt/manage/features/users/ssh_users.sh \
    /opt/manage/features/users/xray_qac.sh \
    /opt/manage/features/users/xray_users.sh \
    /usr/local/lib/autoscript-setup/opt/setup/bin/badvpn-udpgw-launcher.sh \
    /usr/local/lib/autoscript-setup/opt/setup/bin/sshws-control.py \
    /usr/local/lib/autoscript-setup/opt/setup/install/management.sh
do
    [ -f "$f" ] || rollback 1
done

SUCCESS=1

echo
echo "=========================================="
echo " UPDATE PATCH FIX BERHASIL"
echo "=========================================="
echo "Backup: $BACKUP"
echo "Source dan runtime sudah diperbarui."
echo "Akun pelanggan dan database tidak ditimpa."
echo "=========================================="
