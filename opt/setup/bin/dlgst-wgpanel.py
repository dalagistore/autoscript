#!/usr/bin/env python3
import argparse,datetime as dt,fcntl,ipaddress,json,os,pathlib,re,subprocess,sys,tempfile
CONF=pathlib.Path('/etc/wireguard/wg0.conf'); DATA=pathlib.Path('/opt/account/wireguard')
STATE=pathlib.Path('/var/lib/dlgst-wireguard'); SETTINGS=STATE/'settings.json'; LOCK=STATE/'lock'
def run(a,**kw):
 kw.setdefault('check',True)
 kw.setdefault('text',True)
 return subprocess.run(a,**kw)
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
 sync()
def add(x):
 n=x.username.strip();name(n);p=DATA/(n+'.json')
 existing=read(p)
 if existing and existing.get('status') != 'deleted':
  raise ValueError('Username sudah ada')

 if not 1<=x.days<=3650:raise ValueError('Hari aktif 1-3650')
 net=ipaddress.ip_network(cfg()['subnet']);used={a.get('address') for a in users() if a.get('status') in ('active','pending')}
 ip=next((str(i) for i in net.hosts() if str(i)!=cfg()['server_addr'].split('/')[0] and str(i) not in used),None)
 if not ip:raise ValueError('Pool IP penuh')
 priv,pub=keys();now=dt.date.today();a={'username':n,'address':ip,'private_key':priv,'public_key':pub,'created_at':now.isoformat(),'expires_at':(now+dt.timedelta(days=x.days)).isoformat(),'status':'pending'}
 write(p,a);saveclient(a);a['status']='active';write(p,a);sync()
 print(f"User: {n}\nIP: {ip}\nExpiry: {a['expires_at']}\nConfig: {DATA/(n+'.conf')}")
 print("\\n========== WIREGUARD CONFIGURATION (TEXT) ==========")
 print(client(a))
 print("========== WIREGUARD QR CODE ==========")
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
 name(x.username)
 p=DATA/(x.username+'.json')
 a=read(p)

 if not a or a.get('status') == 'deleted':
  raise ValueError('User tidak ditemukan atau sudah dihapus')

 a['private_key'],a['public_key']=keys()
 a['status']='active'
 write(p,a)
 saveclient(a)
 sync()

 config=client(a)

 print()
 print("="*60)
 print("          RESET WIREGUARD PRIVATE KEY")
 print("="*60)
 print(f"USERNAME : {a['username']}")
 print(f"IP       : {a['address']}")
 print(f"CREATED  : {a.get('created_at','-')}")
 print(f"EXPIRY   : {a.get('expires_at','-')}")
 print(f"STATUS   : {a['status'].upper()}")
 print(f"CONFIG   : {DATA/(x.username+'.conf')}")
 print()
 print("="*60)
 print("       WIREGUARD CONFIGURATION (TEXT)")
 print("="*60)
 print(config)
 print("="*60)
 print("                  QR CODE")
 print("="*60)

 run(['qrencode','-t','ANSIUTF8','-o','-'],check=False,input=config)

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
