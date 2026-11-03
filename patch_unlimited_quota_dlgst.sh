#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/root/autoscript"
cd "$ROOT"

for f in \
  opt/manage/features/users/xray_users.sh \
  opt/manage/features/users/ssh_users.sh \
  opt/manage/features/users/xray_qac.sh \
  opt/manage/features/users/ssh_qac.sh; do
  [[ -f "$f" ]] || { echo "ERROR: file tidak ditemukan: $f"; exit 1; }
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/autoscript.backup-unlimited-quota-${STAMP}.tar.gz"
tar -czf "$BACKUP" -C /root autoscript
echo "Backup penuh dibuat: $BACKUP"

python3 - <<'PY'
from pathlib import Path
import sys

root = Path("/root/autoscript")

staged = {}

def edit(rel, replacements):
    p = root / rel
    text = staged.get(rel, p.read_text(encoding="utf-8"))
    original = text
    for old, new, expected in replacements:
        count = text.count(old)
        if count == 0 and new in text:
            continue  # idempotent: already patched
        if count != expected:
            raise SystemExit(
                f"GAGAL: {rel}: pola tidak sesuai; ditemukan {count}, "
                f"seharusnya {expected}. Tidak melanjutkan patch."
            )
        text = text.replace(old, new)
    staged[rel] = text
    if text != original:
        print(f"SIAP DIPATCH {rel}")
    else:
        print(f"OK (sudah sesuai) {rel}")

# Xray account info: creation + regenerated account info.
edit("opt/manage/features/users/xray_users.sh", [
    (
        'quota_gb_disp = fmt_gb(quota_gb)\n',
        'quota_gb_disp = fmt_gb(quota_gb)\n'
        'quota_limit_disp = "UNLIMITED" if quota_bytes <= 0 else f"{quota_gb_disp} GB"\n',
        1
    ),
    (
        'lines.append(f"  Quota Limit : {quota_gb_disp} GB")',
        'lines.append(f"  Quota Limit : {quota_limit_disp}")',
        2
    ),
    (
        'quota_gb_disp = fmt_gb(quota_bytes / (1024 ** 3)) if quota_bytes else "0"\n',
        'quota_gb_disp = fmt_gb(quota_bytes / (1024 ** 3)) if quota_bytes else "0"\n'
        'quota_limit_disp = "UNLIMITED" if quota_bytes <= 0 else f"{quota_gb_disp} GB"\n',
        1
    ),
    (
        'lines.append(f"  Quota Limit : {quota_gb_disp} GB")',
        'lines.append(f"  Quota Limit : {quota_limit_disp}")',
        2
    ),
    (
        'local quota_gb_num quota_bytes\n'
        '  quota_gb_num="$(normalize_gb_input "${quota_gb}")"',
        'local quota_gb_num quota_bytes quota_display\n'
        '  if [[ "${quota_gb}" =~ ^[[:space:]]*0([.]0+)?[[:space:]]*(GB)?[[:space:]]*$ ]]; then\n'
        '    quota_gb_num="0"\n'
        '  else\n'
        '    quota_gb_num="$(normalize_gb_input "${quota_gb}")"\n'
        '  fi',
        1
    ),
    (
        'quota_bytes="$(bytes_from_gb "${quota_gb_num}")"\n',
        'quota_bytes="$(bytes_from_gb "${quota_gb_num}")"\n'
        '  if (( quota_bytes == 0 )); then quota_display="UNLIMITED"; '
        'else quota_display="${quota_gb} GB"; fi\n',
        1
    ),
    (
        'echo "  Quota    : ${quota_gb} GB"',
        'echo "  Quota    : ${quota_display}"',
        1
    ),
])

# SSH account info and creation.
edit("opt/manage/features/users/ssh_users.sh", [
    (
        'print(f"{fmt(b/(1024**3))} GB")',
        'print("UNLIMITED" if b == 0 else f"{fmt(b/(1024**3))} GB")',
        1
    ),
    (
        'local quota_input quota_gb quota_bytes\n',
        'local quota_input quota_gb quota_bytes quota_display\n',
        1
    ),
    (
        'quota_gb="$(normalize_gb_input "${quota_input}")"',
        'if [[ "${quota_input}" =~ ^[[:space:]]*0([.]0+)?[[:space:]]*(GB)?[[:space:]]*$ ]]; then\n'
        '    quota_gb="0"\n'
        '  else\n'
        '    quota_gb="$(normalize_gb_input "${quota_input}")"\n'
        '  fi',
        1
    ),
    (
        'quota_bytes="$(bytes_from_gb "${quota_gb}")"\n',
        'quota_bytes="$(bytes_from_gb "${quota_gb}")"\n'
        '  if (( quota_bytes == 0 )); then quota_display="UNLIMITED"; '
        'else quota_display="${quota_gb} GB"; fi\n',
        1
    ),
    (
        'echo "  Quota    : ${quota_gb} GB"',
        'echo "  Quota    : ${quota_display}"',
        1
    ),
])

# Xray QAC: list and detail display.
edit("opt/manage/features/users/xray_qac.sh", [
    (
        'ql_disp=f"{fmt_gb(ql/bpg)} GB"',
        'ql_disp="UNLIMITED" if ql <= 0 else f"{fmt_gb(ql/bpg)} GB"',
        2
    ),
])

# SSH QAC: list and detail display.
edit("opt/manage/features/users/ssh_qac.sh", [
    (
        'quota_limit_disp = f"{fmt_gb(quota_limit / bpg)} GB"',
        'quota_limit_disp = "UNLIMITED" if quota_limit <= 0 else f"{fmt_gb(quota_limit / bpg)} GB"',
        2
    ),
])

# Commit seluruh file sekaligus setelah semua pola lolos pemeriksaan.
for rel, text in staged.items():
    (root / rel).write_text(text, encoding="utf-8")
print("Semua perubahan berhasil ditulis setelah preflight seluruh file lolos.")
PY

echo
echo "===== VALIDASI SHELL ====="
bash -n opt/manage/features/users/xray_users.sh
bash -n opt/manage/features/users/ssh_users.sh
bash -n opt/manage/features/users/xray_qac.sh
bash -n opt/manage/features/users/ssh_qac.sh

echo
echo "===== VALIDASI POLA UNLIMITED ====="
grep -n -E 'UNLIMITED|quota_display|quota_limit_disp' \
  opt/manage/features/users/xray_users.sh \
  opt/manage/features/users/ssh_users.sh \
  opt/manage/features/users/xray_qac.sh \
  opt/manage/features/users/ssh_qac.sh | head -100

echo
echo "BERHASIL: patch diterapkan pada source /root/autoscript."
echo "Belum menyalin source ke /opt/autoscript dan belum menyentuh data pelanggan."
echo "Backup: $BACKUP"
