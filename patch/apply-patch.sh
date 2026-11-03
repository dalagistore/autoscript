#!/bin/bash
set -Eeuo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$BASE/payload"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/DLGST-UPDATE-PATCH-BACKUP-$STAMP"
MANIFEST="$BASE/SHA256SUMS"

[ -d "$PAYLOAD/source" ] && [ -d "$PAYLOAD/runtime" ] || {
    echo "ERROR: Payload tidak lengkap."
    exit 1
}

echo "===== VALIDASI CHECKSUM ====="
cd "$BASE"
sha256sum -c SHA256SUMS

echo
echo "===== BACKUP ====="
mkdir -p "$BACKUP"

# Backup semua target sebelum perubahan
while IFS= read -r -d '' file; do
    rel="${file#"$PAYLOAD/runtime"/}"
    target="/$rel"

    if [ -e "$target" ]; then
        mkdir -p "$BACKUP/runtime/$(dirname "$rel")"
        cp -a "$target" "$BACKUP/runtime/$rel"
    else
        mkdir -p "$BACKUP/missing/$(dirname "$rel")"
        touch "$BACKUP/missing/$rel"
    fi
done < <(find "$PAYLOAD/runtime" -type f -print0)

while IFS= read -r -d '' file; do
    rel="${file#"$PAYLOAD/source"/}"
    target="/opt/autoscript/$rel"

    if [ -e "$target" ]; then
        mkdir -p "$BACKUP/source/$(dirname "$rel")"
        cp -a "$target" "$BACKUP/source/$rel"
    else
        mkdir -p "$BACKUP/source-missing/$(dirname "$rel")"
        touch "$BACKUP/source-missing/$rel"
    fi
done < <(find "$PAYLOAD/source" -type f -print0)

echo "Backup: $BACKUP"

rollback() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo
        echo "ERROR: Patch gagal. Menjalankan rollback..."

        cp -a "$BACKUP/runtime/." / 2>/dev/null || true
        cp -a "$BACKUP/source/." /opt/autoscript/ 2>/dev/null || true

        while IFS= read -r -d '' f; do
            rel="${f#"$BACKUP/missing"/}"
            rm -f "/$rel"
        done < <(find "$BACKUP/missing" -type f -print0 2>/dev/null || true)

        while IFS= read -r -d '' f; do
            rel="${f#"$BACKUP/source-missing"/}"
            rm -f "/opt/autoscript/$rel"
        done < <(find "$BACKUP/source-missing" -type f -print0 2>/dev/null || true)

        echo "Rollback selesai. Periksa backup: $BACKUP"
    fi
    exit "$rc"
}
trap rollback EXIT

echo
echo "===== UPDATE SOURCE ====="
cp -a "$PAYLOAD/source/." /opt/autoscript/

echo
echo "===== UPDATE RUNTIME ====="
cp -a "$PAYLOAD/runtime/." /

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
 /opt/autoscript/account-portal/web/dist \
 /opt/account-portal/web/dist

echo
echo "===== VERIFIKASI FILE RUNTIME ====="
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
    [ -f "$f" ] || {
        echo "ERROR: File runtime hilang: $f"
        exit 1
    }
done

echo
echo "PATCH BERHASIL DIPASANG."
echo "Backup: $BACKUP"
echo "Akun pelanggan dan database tidak ditimpa."
trap - EXIT
