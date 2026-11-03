#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/root/autoscript"
cd "$ROOT"

echo "=== DLGST UNLIMITED QUOTA PATCH ==="
echo "Source: $ROOT"
command -v rsync >/dev/null || { echo "ERROR: rsync belum terpasang. Pasang dengan: apt-get update && apt-get install -y rsync"; exit 1; }

required=(
  opt/manage/features/users/xray_users.sh
  opt/manage/features/users/ssh_users.sh
  opt/manage/features/users/xray_qac.sh
  opt/manage/features/users/ssh_qac.sh
  account-portal/app/data.py
  account-portal/web/src/components/portal/quota-card.tsx
)
for f in "${required[@]}"; do
  [[ -f "$f" ]] || { echo "ERROR: file tidak ditemukan: $f"; exit 1; }
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/autoscript.backup-unlimited-quota-full-${STAMP}.tar.gz"
tar -czf "$BACKUP" -C /root autoscript
echo "Backup source penuh: $BACKUP"

python3 - <<'PY'
from pathlib import Path
import sys

ROOT = Path("/root/autoscript")
staged = {}

def patch(rel, old, new, expected=1):
    p = ROOT / rel
    text = staged.get(rel, p.read_text(encoding="utf-8"))
    count = text.count(old)
    if count == 0 and new in text:
        print(f"OK sudah dipatch: {rel}")
        staged[rel] = text
        return
    if count != expected:
        raise SystemExit(
            f"ABORT: {rel}: pola ditemukan {count} kali, "
            f"seharusnya {expected}. Tidak ada file yang ditulis."
        )
    staged[rel] = text.replace(old, new)
    print(f"SIAP: {rel} ({expected} penggantian)")

# ---------------- Xray: input 0 = unlimited ----------------
patch(
    "opt/manage/features/users/xray_users.sh",
    '  local quota_gb_num quota_bytes\n'
    '  quota_gb_num="$(normalize_gb_input "${quota_gb}")"',
    '  local quota_gb_num quota_bytes quota_display\n'
    '  if [[ "${quota_gb}" =~ ^[[:space:]]*0([.]0+)?[[:space:]]*(GB)?[[:space:]]*$ ]]; then\n'
    '    quota_gb_num="0"\n'
    '  else\n'
    '    quota_gb_num="$(normalize_gb_input "${quota_gb}")"\n'
    '  fi',
)
patch(
    "opt/manage/features/users/xray_users.sh",
    '  quota_bytes="$(bytes_from_gb "${quota_gb_num}")"\n',
    '  quota_bytes="$(bytes_from_gb "${quota_gb_num}")"\n'
    '  if (( quota_bytes == 0 )); then quota_display="UNLIMITED"; '
    'else quota_display="${quota_gb_num} GB"; fi\n',
)
patch(
    "opt/manage/features/users/xray_users.sh",
    '  echo "  Quota    : ${quota_gb} GB"',
    '  echo "  Quota    : ${quota_display}"',
)

# Xray account information: creation and regenerated info.
patch(
    "opt/manage/features/users/xray_users.sh",
    'quota_gb_disp = fmt_gb(quota_gb)\n',
    'quota_gb_disp = fmt_gb(quota_gb)\n'
    'quota_limit_disp = "UNLIMITED" if quota_bytes <= 0 else f"{quota_gb_disp} GB"\n',
)
patch(
    "opt/manage/features/users/xray_users.sh",
    'lines.append(f"  Quota Limit : {quota_gb_disp} GB")',
    'lines.append(f"  Quota Limit : {quota_limit_disp}")',
    expected=2,
)
patch(
    "opt/manage/features/users/xray_users.sh",
    'quota_gb_disp = fmt_gb(quota_bytes / (1024 ** 3)) if quota_bytes else "0"\n',
    'quota_gb_disp = fmt_gb(quota_bytes / (1024 ** 3)) if quota_bytes else "0"\n'
    'quota_limit_disp = "UNLIMITED" if quota_bytes <= 0 else f"{quota_gb_disp} GB"\n',
)

# ---------------- SSH: input and account information ----------------
patch(
    "opt/manage/features/users/ssh_users.sh",
    'print(f"{fmt(b/(1024**3))} GB")',
    'print("UNLIMITED" if b <= 0 else f"{fmt(b/(1024**3))} GB")',
)
patch(
    "opt/manage/features/users/ssh_users.sh",
    '  local quota_input quota_gb quota_bytes\n',
    '  local quota_input quota_gb quota_bytes quota_display\n',
)
patch(
    "opt/manage/features/users/ssh_users.sh",
    '  quota_gb="$(normalize_gb_input "${quota_input}")"',
    '  if [[ "${quota_input}" =~ ^[[:space:]]*0([.]0+)?[[:space:]]*(GB)?[[:space:]]*$ ]]; then\n'
    '    quota_gb="0"\n'
    '  else\n'
    '    quota_gb="$(normalize_gb_input "${quota_input}")"\n'
    '  fi',
)
patch(
    "opt/manage/features/users/ssh_users.sh",
    '  quota_bytes="$(bytes_from_gb "${quota_gb}")"\n',
    '  quota_bytes="$(bytes_from_gb "${quota_gb}")"\n'
    '  if (( quota_bytes == 0 )); then quota_display="UNLIMITED"; '
    'else quota_display="${quota_gb} GB"; fi\n',
)
# Summary may be formatted differently in some revisions; account info writer
# above is the authoritative persistent account information display.

# ---------------- QAC displays ----------------
patch(
    "opt/manage/features/users/xray_qac.sh",
    'ql_disp=f"{fmt_gb(ql/bpg)} GB"',
    'ql_disp="UNLIMITED" if ql <= 0 else f"{fmt_gb(ql/bpg)} GB"',
    expected=2,
)
patch(
    "opt/manage/features/users/ssh_qac.sh",
    'quota_limit_disp = f"{fmt_gb(quota_limit / bpg)} GB"',
    'quota_limit_disp = "UNLIMITED" if quota_limit <= 0 else f"{fmt_gb(quota_limit / bpg)} GB"',
    expected=2,
)

# ---------------- Customer portal backend ----------------
patch(
    "account-portal/app/data.py",
    '"quota_limit": _human_bytes(quota_limit_bytes) if quota_limit_bytes > 0 else "Unlimited",',
    '"quota_limit": _human_bytes(quota_limit_bytes) if quota_limit_bytes > 0 else "UNLIMITED",',
)
patch(
    "account-portal/app/data.py",
    '"quota_remaining": _human_bytes(quota_remaining_bytes) if quota_limit_bytes > 0 else "Unlimited",',
    '"quota_remaining": _human_bytes(quota_remaining_bytes) if quota_limit_bytes > 0 else "UNLIMITED",',
)

# ---------------- Customer portal frontend ----------------
patch(
    "account-portal/web/src/components/portal/quota-card.tsx",
    '  const percent = quotaPercent(summary)\n'
    '  const tone = percent >= 90 ? "destructive" : percent >= 60 ? "warning" : "success"\n'
    '  const label = percent >= 90 ? "Hampir Habis" : percent >= 60 ? "Perlu Dipantau" : "Aman"',
    '  const isUnlimited = summary.quota_limit_bytes <= 0\n'
    '  const percent = quotaPercent(summary)\n'
    '  const tone = isUnlimited ? "success" : percent >= 90 ? "destructive" : percent >= 60 ? "warning" : "success"\n'
    '  const label = isUnlimited ? "Tanpa Batas" : percent >= 90 ? "Hampir Habis" : percent >= 60 ? "Perlu Dipantau" : "Aman"',
)
patch(
    "account-portal/web/src/components/portal/quota-card.tsx",
    '<Badge variant="accent">{percent}% terpakai</Badge>',
    '<Badge variant="accent">{isUnlimited ? "UNLIMITED" : `${percent}% terpakai`}</Badge>',
)
patch(
    "account-portal/web/src/components/portal/quota-card.tsx",
    '        <div className="h-3 overflow-hidden rounded-full bg-muted">\n'
    '          <div className="h-full rounded-full bg-primary transition-[width]" style={{ width: `${percent}%` }} />\n'
    '        </div>',
    '        {!isUnlimited && (\n'
    '          <div className="h-3 overflow-hidden rounded-full bg-muted">\n'
    '            <div className="h-full rounded-full bg-primary transition-[width]" style={{ width: `${percent}%` }} />\n'
    '          </div>\n'
    '        )}',
)

# All preflight checks have passed. Only now write files.
for rel, text in staged.items():
    (ROOT / rel).write_text(text, encoding="utf-8")
print("Semua patch source berhasil ditulis.")
PY

echo
echo "===== VALIDASI SHELL ====="
bash -n opt/manage/features/users/xray_users.sh
bash -n opt/manage/features/users/ssh_users.sh
bash -n opt/manage/features/users/xray_qac.sh
bash -n opt/manage/features/users/ssh_qac.sh

echo
echo "===== VALIDASI PYTHON PORTAL ====="
python3 -m py_compile account-portal/app/data.py

echo
echo "===== BUILD FRONTEND PORTAL ====="
(
  cd account-portal/web
  npm ci --no-audit --no-fund
  npm run build
)
[[ -f account-portal/web/dist/index.html ]] || {
  echo "ERROR: build frontend tidak menghasilkan dist/index.html"
  exit 1
}

echo
echo "===== SINKRONISASI SOURCE MIRROR ====="
for f in \
  opt/manage/features/users/xray_users.sh \
  opt/manage/features/users/ssh_users.sh \
  opt/manage/features/users/xray_qac.sh \
  opt/manage/features/users/ssh_qac.sh; do
  install -D -m 0644 "$f" "/opt/autoscript/$f"
done
rsync -a --delete \
  --exclude='.venv/' \
  --exclude='web/node_modules/' \
  account-portal/ /opt/autoscript/account-portal/

echo
echo "===== UPDATE PORTAL AKTIF ====="
command -v rsync >/dev/null || {
  echo "ERROR: rsync tidak tersedia. Source telah dipatch; deployment belum disinkronkan."
  exit 1
}
rsync -a --delete \
  --exclude='.venv/' \
  --exclude='web/node_modules/' \
  account-portal/ /opt/account-portal/

echo
echo "===== VALIDASI DEPLOYMENT DAN RESTART ====="
/opt/account-portal/.venv/bin/python -m py_compile \
  /opt/account-portal/app/data.py
systemctl restart account-portal
sleep 2
systemctl is-active --quiet account-portal || {
  systemctl status account-portal --no-pager -l || true
  journalctl -u account-portal -n 80 --no-pager || true
  echo "ERROR: account-portal gagal aktif setelah restart."
  exit 1
}
if command -v curl >/dev/null; then
  curl -fsS http://127.0.0.1:7082/openapi.json >/dev/null
fi

echo
echo "===== HASIL ====="
git status --short
echo "PATCH BERHASIL."
echo "Backup penuh: $BACKUP"
echo "Source utama, mirror, dan portal aktif telah diperbarui."
echo "Catatan: perubahan belum di-commit atau di-push ke GitHub."
