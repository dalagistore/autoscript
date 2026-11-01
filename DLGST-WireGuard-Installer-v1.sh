#!/usr/bin/env bash
# DLGST WireGuard installer for Debian 12. Does not replace Xray/SSH/WARP.
set -Eeuo pipefail
umask 077
[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }

ACTIVE=/opt/manage
SOURCE=/opt/autoscript/opt/manage
LIB=/usr/local/lib/dlgst-wireguard
FW=/usr/local/sbin/dlgst-wg-firewall
CONF=/etc/wireguard/wg0.conf
DATA=/opt/account/wireguard
STATE=/var/lib/dlgst-wireguard
PORT=${WG_PORT:-51820}
ENDPOINT=${WG_ENDPOINT:-id2.dlgst.cloud}
SUBNET=${WG_SUBNET:-10.66.66.0/24}
SERVER_ADDR=${WG_SERVER_ADDR:-10.66.66.1/24}
OUT_IF=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
BACKUP=/root/DLGST-WIREGUARD-BACKUP-$(date +%Y%m%d-%H%M%S)
COMMITTED=0
OLD_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)

fail(){ echo "[DLGST-WG] ERROR: $*" >&2; exit 1; }
rollback(){
  rc=$?
  if [[ $rc -ne 0 && $COMMITTED -eq 0 ]]; then
    echo "[ROLLBACK] Mengembalikan file panel..."
    systemctl disable --now dlgst-wireguard-expire.timer >/dev/null 2>&1 || true
    systemctl disable --now wg-quick@wg0 >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/dlgst-wireguard-expire.{service,timer} "$FW" /etc/sysctl.d/99-dlgst-wireguard.conf "$CONF"
    [[ ! -f $BACKUP/active-users.sh ]] || cp -a "$BACKUP/active-users.sh" "$ACTIVE/features/users.sh"
    [[ ! -f $BACKUP/source-users.sh ]] || cp -a "$BACKUP/source-users.sh" "$SOURCE/features/users.sh"
    [[ ! -f $BACKUP/active-menu.sh ]] || cp -a "$BACKUP/active-menu.sh" "$ACTIVE/menus/main_menu.sh"
    [[ ! -f $BACKUP/source-menu.sh ]] || cp -a "$BACKUP/source-menu.sh" "$SOURCE/menus/main_menu.sh"
    rm -f "$ACTIVE/features/users/wireguard_users.sh" "$SOURCE/features/users/wireguard_users.sh"
    nft delete table ip dlgst_wireguard >/dev/null 2>&1 || true
    sysctl -w "net.ipv4.ip_forward=$OLD_FORWARD" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    echo "[ROLLBACK] Backup tersedia: $BACKUP"
  fi
  exit "$rc"
}
trap rollback EXIT

[[ -d $ACTIVE && -f $ACTIVE/features/users.sh && -f $ACTIVE/menus/main_menu.sh ]] || fail "Struktur /opt/manage tidak ditemukan."
[[ -d $SOURCE && -f $SOURCE/features/users.sh && -f $SOURCE/menus/main_menu.sh ]] || fail "Source DLGST tidak ditemukan."
[[ $PORT =~ ^[0-9]+$ ]] && ((PORT>0 && PORT<65536)) || fail "Port tidak valid."
[[ $ENDPOINT =~ ^[A-Za-z0-9.-]+$ ]] || fail "Endpoint tidak valid."
[[ -n $OUT_IF ]] || fail "Interface internet tidak ditemukan."
python3 - "$SUBNET" "$SERVER_ADDR" <<'PY'
import ipaddress,sys
n=ipaddress.ip_network(sys.argv[1],strict=True); a=ipaddress.ip_interface(sys.argv[2])
if n.version!=4 or a.version!=4 or a.ip not in n or n.prefixlen>29: raise SystemExit("Subnet/server address tidak valid.")
PY
[[ ! -e $CONF ]] || fail "$CONF sudah ada, tidak akan ditimpa."
! ip link show wg0 >/dev/null 2>&1 || fail "wg0 sudah ada."
! ss -H -lun "sport = :$PORT" | grep -q . || fail "UDP port $PORT sedang digunakan."
! nft list table ip dlgst_wireguard >/dev/null 2>&1 || fail "Tabel nftables dlgst_wireguard sudah ada."
[[ ! -e /etc/sysctl.d/99-dlgst-wireguard.conf ]] || fail "File sysctl WireGuard sudah ada; tidak akan ditimpa."
[[ ! -e /etc/systemd/system/dlgst-wireguard-expire.service ]] || fail "Unit expiry service sudah ada; tidak akan ditimpa."
[[ ! -e /etc/systemd/system/dlgst-wireguard-expire.timer ]] || fail "Unit expiry timer sudah ada; tidak akan ditimpa."
grep -q '3|WireGuard Users' "$ACTIVE/menus/main_menu.sh" || fail "Menu nomor 3 WireGuard Users belum ada."
grep -q 'wireguard_users_menu' "$ACTIVE/menus/main_menu.sh" || fail "Routing wireguard_users_menu belum ada."

mkdir -m 700 -p "$BACKUP"
cp -a "$ACTIVE/features/users.sh" "$BACKUP/active-users.sh"
cp -a "$SOURCE/features/users.sh" "$BACKUP/source-users.sh"
cp -a "$ACTIVE/menus/main_menu.sh" "$BACKUP/active-menu.sh"
cp -a "$SOURCE/menus/main_menu.sh" "$BACKUP/source-menu.sh"
[[ ! -e $ACTIVE/features/users/wireguard_users.sh ]] || fail "Modul WireGuard aktif sudah ada."
[[ ! -e $SOURCE/features/users/wireguard_users.sh ]] || fail "Modul WireGuard source sudah ada."

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wireguard-tools nftables qrencode python3 iproute2

install -d -m 700 /etc/wireguard "$DATA" "$LIB" "$STATE"

cat > "$FW" <<'FIREWALL'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
 up)
  subnet="${2:?subnet wajib}"; iface="${3:?interface wajib}"
  python3 - "$subnet" "$iface" <<'PY'
import ipaddress,re,sys
ipaddress.ip_network(sys.argv[1],strict=True)
if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,64}',sys.argv[2]): raise SystemExit("Interface tidak valid")
PY
  if nft list table ip dlgst_wireguard >/dev/null 2>&1; then
    echo "Tabel dlgst_wireguard sudah ada; menolak menimpa." >&2; exit 1
  fi
  nft -f - <<NFT
table ip dlgst_wireguard {
 chain postrouting {
  type nat hook postrouting priority srcnat; policy accept;
  ip saddr $subnet oifname "$iface" masquerade
 }
}
NFT
  ;;
 down) nft list table ip dlgst_wireguard >/dev/null 2>&1 && nft delete table ip dlgst_wireguard || true ;;
 *) echo "Usage: $0 {up SUBNET IFACE|down}" >&2; exit 2 ;;
esac
FIREWALL
chmod 700 "$FW"

cat > "$LIB/wgpanel.py" <<'PY'
#!/usr/bin/env python3
import argparse,datetime as dt,fcntl,ipaddress,json,os,pathlib,re,subprocess,sys,tempfile
CONF=pathlib.Path('/etc/wireguard/wg0.conf'); DATA=pathlib.Path('/opt/account/wireguard')
STATE=pathlib.Path('/var/lib/dlgst-wireguard'); SETTINGS=STATE/'settings.json'; LOCK=STATE/'lock'
def run(a,**kw): return subprocess.run(a,check=True,text=True,**kw)
def read(p,d=None):
 try:
  with open(p,encoding='utf-8') as f:return json.load(f)
 except FileNotFoundError:return d
def write(p,o):
 p.parent.mkdir(parents=True,exist_ok=True); fd,t=tempfile.mkstemp(dir=p.parent)
 with os.fdopen(fd,'w') as f:json.dump(o,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
 os.chmod(t,0o600);os.replace(t,p)
def cfg():return read(SETTINGS,{})
def users():return [x for p in DATA.glob('*.json') if isinstance((x:=read(p)),dict)]
def name(n):
 if not re.fullmatch(r'[A-Za-z0-9_-]{1,32}',n):raise ValueError('Username 1-32 karakter: huruf, angka, _ atau -')
def keys():
 a=run(['wg','genkey'],stdout=subprocess.PIPE).stdout.strip()
 b=run(['wg','pubkey'],input=a+'\n',stdout=subprocess.PIPE).stdout.strip()
 return a,b
def serverkey():
 p=STATE/'server_private.key'
 if not p.exists():
  a,b=keys();p.write_text(a+'\n');os.chmod(p,0o600);(STATE/'server_public.key').write_text(b+'\n');os.chmod(STATE/'server_public.key',0o600)
 return p.read_text().strip()
def serverpub():
 p=STATE/'server_public.key'
 if not p.exists():serverkey()
 return p.read_text().strip()
def client(a):
 s=cfg()
 return '\n'.join(['[Interface]',f"PrivateKey = {a['private_key']}",f"Address = {a['address']}/32",'DNS = 1.1.1.1, 1.0.0.1','[Peer]',f"PublicKey = {serverpub()}",'AllowedIPs = 0.0.0.0/0',f"Endpoint = {s['endpoint']}:{s['port']}",'PersistentKeepalive = 25',''])
def saveclient(a):
 p=DATA/(a['username']+'.conf');p.write_text(client(a));os.chmod(p,0o600)
def serverconf():
 s=cfg();lines=['[Interface]',f"Address = {s['server_addr']}",f"ListenPort = {s['port']}",f"PrivateKey = {serverkey()}","SaveConfig = false",f"PostUp = /usr/local/sbin/dlgst-wg-firewall up {s['subnet']} {s['out_iface']}","PostDown = /usr/local/sbin/dlgst-wg-firewall down",'']
 today=dt.date.today()
 for a in users():
  try:valid=a.get('status')=='active' and dt.date.fromisoformat(a['expires_at'])>=today
  except Exception:valid=False
  if valid:lines += ['[Peer]',f"# {a['username']}",f"PublicKey = {a['public_key']}",f"AllowedIPs = {a['address']}/32",'']
 t=CONF.with_suffix('.tmp');t.write_text('\n'.join(lines));os.chmod(t,0o600);os.replace(t,CONF)
def sync():
 serverconf()
 if subprocess.run(['ip','link','show','wg0'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:
  run(['bash','-c','wg syncconf wg0 <(wg-quick strip wg0)'])
 else:run(['systemctl','enable','--now','wg-quick@wg0'])
def expire(_=None):
 today=dt.date.today();changed=False
 for a in users():
  if a.get('status')!='active':continue
  try:old=dt.date.fromisoformat(a['expires_at'])<today
  except Exception:old=True
  if old:a['status']='expired';write(DATA/(a['username']+'.json'),a);changed=True
 if changed:sync()
def add(x):
 n=x.username.strip();name(n);p=DATA/(n+'.json')
 if p.exists():raise ValueError('Username sudah ada')
 if not 1<=x.days<=3650:raise ValueError('Hari aktif 1-3650')
 net=ipaddress.ip_network(cfg()['subnet']);used={a.get('address') for a in users() if a.get('status') in ('active','pending')}
 ip=next((str(i) for i in net.hosts() if str(i)!=cfg()['server_addr'].split('/')[0] and str(i) not in used),None)
 if not ip:raise ValueError('Pool IP penuh')
 priv,pub=keys();now=dt.date.today();a={'username':n,'address':ip,'private_key':priv,'public_key':pub,'created_at':now.isoformat(),'expires_at':(now+dt.timedelta(days=x.days)).isoformat(),'status':'pending'}
 write(p,a);saveclient(a);a['status']='active';write(p,a);sync()
 print(f"User: {n}\nIP: {ip}\nExpiry: {a['expires_at']}\nConfig: {DATA/(n+'.conf')}")
 run(['qrencode','-t','ANSIUTF8','-o','-'],check=False,input=client(a))
def delete(x):
 name(x.username);p=DATA/(x.username+'.json');a=read(p)
 if not a:raise ValueError('User tidak ditemukan')
 a['status']='deleted';write(p,a);(DATA/(x.username+'.conf')).unlink(missing_ok=True);sync();print('User dihapus')
def expiry(x):
 name(x.username);p=DATA/(x.username+'.json');a=read(p)
 if not a:raise ValueError('User tidak ditemukan')
 if not 1<=x.days<=3650:raise ValueError('Hari aktif 1-3650')
 a['expires_at']=(dt.date.today()+dt.timedelta(days=x.days)).isoformat();a['status']='active';write(p,a);saveclient(a);sync();print(a['expires_at'])
def reset(x):
 name(x.username);p=DATA/(x.username+'.json');a=read(p)
 if not a:raise ValueError('User tidak ditemukan')
 a['private_key'],a['public_key']=keys();a['status']='active';write(p,a);saveclient(a);sync();print('Key direset:',DATA/(x.username+'.conf'))
 run(['qrencode','-t','ANSIUTF8','-o','-'],check=False,input=client(a))
def listing(_):
 expire();print(f"{'USERNAME':20} {'IP':16} {'EXPIRY':12} STATUS")
 for a in users():print(f"{a['username'][:20]:20} {a['address']:16} {a['expires_at']:12} {a['status']}")
def main():
 p=argparse.ArgumentParser();s=p.add_subparsers(dest='cmd',required=True)
 for cmd,fn,extra in [('add',add,1),('delete',delete,0),('expiry',expiry,1),('reset',reset,0),('list',listing,0),('expire',expire,0)]:
  q=s.add_parser(cmd)
  if cmd in ('add','delete','expiry','reset'):q.add_argument('username')
  if extra:q.add_argument('days',type=int)
  q.set_defaults(fn=fn)
 x=p.parse_args();STATE.mkdir(parents=True,exist_ok=True)
 with LOCK.open('w') as f:fcntl.flock(f,fcntl.LOCK_EX);x.fn(x)
if __name__=='__main__':
 try:main()
 except Exception as e:print('ERROR:',e,file=sys.stderr);sys.exit(1)
PY
chmod 700 "$LIB/wgpanel.py"

OUT_IF="$OUT_IF" python3 - "$PORT" "$ENDPOINT" "$SUBNET" "$SERVER_ADDR" <<'PY'
import json,os,sys
port,endpoint,subnet,addr=sys.argv[1:]
p='/var/lib/dlgst-wireguard/settings.json'
with open(p,'w') as f:json.dump({'port':int(port),'endpoint':endpoint,'subnet':subnet,'server_addr':addr,'out_iface':os.environ['OUT_IF']},f,indent=2);f.write('\n')
os.chmod(p,0o600)
PY
wg genkey > "$STATE/server_private.key"
wg pubkey < "$STATE/server_private.key" > "$STATE/server_public.key"
chmod 600 "$STATE"/server_*.key

printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-dlgst-wireguard.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

for f in "$ACTIVE/features/users.sh" "$SOURCE/features/users.sh"; do
 if ! grep -q 'features/users/wireguard_users.sh' "$f"; then
  python3 - "$f" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text();n='  "features/users/ssh_qac.sh"; do'
if n not in s:raise SystemExit('Loader tidak sesuai: '+str(p))
p.write_text(s.replace(n,'  "features/users/ssh_qac.sh" \\\n  "features/users/wireguard_users.sh"; do',1))
PY
 fi
done

mkdir -p "$ACTIVE/features/users" "$SOURCE/features/users"
cat > "$ACTIVE/features/users/wireguard_users.sh" <<'BASH'
#!/usr/bin/env bash
WG_PANEL_BIN="${WG_PANEL_BIN:-/usr/local/lib/dlgst-wireguard/wgpanel.py}"
wireguard_users_menu() {
 local c u d
 while true; do
  echo "===== DLGST WIREGUARD USERS ====="
  echo "1) Add User  2) Delete User  3) Set Expiry"
  echo "4) Reset Key  5) List Users  0) Back"
  read -r -p "Pilih: " c || return
  case "$c" in
   1) read -r -p "Username: " u; read -r -p "Hari: " d; "$WG_PANEL_BIN" add "$u" "$d"; read -r -p "ENTER..." _ ;;
   2) read -r -p "Username: " u; "$WG_PANEL_BIN" delete "$u"; read -r -p "ENTER..." _ ;;
   3) read -r -p "Username: " u; read -r -p "Hari: " d; "$WG_PANEL_BIN" expiry "$u" "$d"; read -r -p "ENTER..." _ ;;
   4) read -r -p "Username: " u; "$WG_PANEL_BIN" reset "$u"; read -r -p "ENTER..." _ ;;
   5) "$WG_PANEL_BIN" list; read -r -p "ENTER..." _ ;;
   0|b|back) return ;;
   *) echo "Pilihan tidak valid"; sleep 1 ;;
  esac
 done
}
BASH
chmod 644 "$ACTIVE/features/users/wireguard_users.sh"
cp -a "$ACTIVE/features/users/wireguard_users.sh" "$SOURCE/features/users/wireguard_users.sh"

grep -q '3|WireGuard Users' "$ACTIVE/menus/main_menu.sh" || fail "Menu nomor 3 tidak ditemukan."
grep -q 'wireguard_users_menu' "$ACTIVE/menus/main_menu.sh" || fail "Routing fungsi menu tidak ditemukan."
grep -q '3|WireGuard Users' "$SOURCE/menus/main_menu.sh" || fail "Menu source nomor 3 tidak ditemukan."
grep -q 'wireguard_users_menu' "$SOURCE/menus/main_menu.sh" || fail "Routing source tidak ditemukan."

python3 -m py_compile "$LIB/wgpanel.py"
"$LIB/wgpanel.py" expire
cat > /etc/systemd/system/dlgst-wireguard-expire.service <<EOF
[Unit]
Description=DLGST WireGuard expiry check
After=wg-quick@wg0.service
[Service]
Type=oneshot
ExecStart=$LIB/wgpanel.py expire
EOF
cat > /etc/systemd/system/dlgst-wireguard-expire.timer <<'EOF'
[Unit]
Description=Hourly DLGST WireGuard expiry check
[Timer]
OnCalendar=hourly
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now wg-quick@wg0
systemctl enable --now dlgst-wireguard-expire.timer
systemctl is-active --quiet wg-quick@wg0 || fail "WireGuard service gagal aktif."
systemctl is-active --quiet dlgst-wireguard-expire.timer || fail "Expiry timer gagal aktif."
wg show wg0
"$LIB/wgpanel.py" list
COMMITTED=1
trap - EXIT
echo
echo "DLGST WIREGUARD BERHASIL DIPASANG"
echo "Endpoint : $ENDPOINT:$PORT/UDP"
echo "Interface: wg0 | Subnet: $SUBNET"
echo "Backup   : $BACKUP"
echo "Pastikan UDP $PORT diizinkan pada firewall provider VPS."
