import contextlib, io, os, sys, json, pathlib, subprocess, socket, threading, ctypes, time, signal, tempfile, shutil
assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net'), 'Run only under unshare -n'
B=json.load(sys.stdin); ROOT=pathlib.Path(tempfile.mkdtemp(prefix='antiabuse-netns-'));rows=[];children=[]
def run(a,check=True,input=None):
 r=subprocess.run(a,input=input,text=True,capture_output=True,timeout=30)
 if check and r.returncode:raise RuntimeError(str(a[:2])+': '+r.stderr[-400:])
 return r
def result(name,ok,**kw):rows.append({'check':name,'passed':bool(ok),**kw})
def make_ns():
 pid=os.fork()
 if pid==0:
  if ctypes.CDLL(None,use_errno=True).unshare(0x40000000)!=0:os._exit(2)
  while True:time.sleep(60)
 children.append(pid);time.sleep(.1);return pid
def ns(pid,a,**kw):return run(['nsenter','-t',str(pid),'-n']+a,**kw)
def link(pid,name,v4,v6):
 run(['ip','link','add',name,'type','veth','peer','name',name+'c']);run(['ip','link','set',name+'c','netns',str(pid)])
 run(['ip','addr','add',v4+'.1/24','dev',name]);run(['ip','-6','addr','add',v6+'1/64','dev',name,'nodad']);run(['ip','link','set',name,'up'])
 ns(pid,['ip','link','set','lo','up']);ns(pid,['ip','addr','add',v4+'.2/24','dev',name+'c']);ns(pid,['ip','-6','addr','add',v6+'2/64','dev',name+'c','nodad']);ns(pid,['ip','link','set',name+'c','up'])
 ns(pid,['ip','route','add','default','via',v4+'.1']);ns(pid,['ip','-6','route','add','default','via',v6+'1'])
def server():
 import selectors
 s=selectors.DefaultSelector()
 ports=[22,25,53,80,443,465,587,2222,2525,6881,6999,2710,6969,16881,51413,53442]
 for fam,addr in [(socket.AF_INET,'0.0.0.0'),(socket.AF_INET6,'::')]:
  for typ in [socket.SOCK_STREAM,socket.SOCK_DGRAM]:
   addresses=[addr] if typ==socket.SOCK_STREAM else (['198.18.10.1','198.18.20.2','198.18.20.3','198.18.20.200','8.8.8.8','203.0.113.53'] if fam==socket.AF_INET else ['2001:db8:10::1','2001:db8:20::2','2001:db8:20::200'])
   for local in addresses:
    for port in ports:
     q=socket.socket(fam,typ);q.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
     if fam==socket.AF_INET6:q.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
     try:q.bind((local,port))
     except OSError:q.close();continue
     if typ==socket.SOCK_STREAM:q.listen(40)
     s.register(q,selectors.EVENT_READ,typ)
 while True:
  for key,_ in s.select():
   q=key.fileobj
   if key.data==socket.SOCK_STREAM:
    c,_=q.accept()
    try:
     if c.getsockname()[1] == 80:
      c.settimeout(.2);c.recv(4096)
     c.sendall(b'OK')
    except OSError:pass
    c.close()
   else:
    b,a=q.recvfrom(2048)
    try:q.sendto(b,a)
    except OSError:pass
def connect(address,port,udp=False,source=None):
 s=socket.socket(socket.AF_INET6 if ':'in address else socket.AF_INET,socket.SOCK_DGRAM if udp else socket.SOCK_STREAM);s.settimeout(.25)
 try:
  if source:s.bind(tuple(source) if isinstance(source,list) else (source,0))
  s.connect((address,port))
  if udp:s.send(b'OK')
  return s.recv(2)==b'OK'
 except OSError:return False
 finally:s.close()
def connect_payload(address, payload, udp=False):
 s=socket.socket(socket.AF_INET6 if ':' in address else socket.AF_INET,socket.SOCK_DGRAM if udp else socket.SOCK_STREAM);s.settimeout(.3)
 try:
  s.connect((address,80));s.sendall(payload);return s.recv(2)==(payload[:2] if udp else b'OK')
 except OSError:return False
 finally:s.close()
def client(pid,address,port,udp=False,source=None):
 code='import socket\n'+B['connect_source']+'\nprint(int(connect('+repr(address)+','+str(port)+','+repr(udp)+','+repr(source)+')))'
 return ns(pid,['python3','-c',code]).stdout.strip()=='1'
def flush():run(['nft','flush','ruleset'])
def generate(name):
 pre='''set -Eeuo pipefail
systemctl() { return 1; }
ufw() { echo 'Status: inactive'; return 0; }
curl() { if [[ "$*" == *drop_v6* ]]; then printf '%s\\n' '{"cidr":"2001:db8:20::200/128","sblid":"SBLTEST"}'; elif [[ "$*" == *drop_v4* ]]; then printf '%s\\n' '{"cidr":"198.18.20.200/32","sblid":"SBLTEST"}'; else printf '%s\\n' '198.18.20.200/32 ; SBLTEST'; fi; }
resolvectl() { echo '198.18.20.2 2001:db8:20::2'; }
export -f systemctl ufw curl resolvectl
bool_true() { [[ "$1" == 1 ]]; }
cleanup_installer_iptables_runtime() { :; }
cleanup_installer_ufw_rules() { :; }
warn() { :; }
'''
 pre+=f'FIREWALL_SCRIPT={ROOT}/firewall.sh\nFIREWALL_SERVICE={ROOT}/firewall.service\nexport REMNANODE_SPAMHAUS_CACHE_DIR={ROOT}/spamhaus-cache\n'
 for n in ['SPAMHAUS_EGRESS_GUARD','OUTBOUND_SSH_GUARD','DNS_REFLECTION_GUARD','BITTORRENT_GUARD']:
  pre+=f'{n}_SCRIPT={ROOT}/{n}.sh\n{n}_SERVICE={ROOT}/{n}.service\n'
 pre+=f'SPAMHAUS_EGRESS_GUARD_TIMER={ROOT}/spam.timer\nPANEL_IPS="198.18.10.2 2001:db8:10::2"\nNODE_PORT=2222\nPUBLIC_TCP_PORTS=443\nPUBLIC_UDP_PORTS=443\nSMTP_EGRESS_PORTS=25,465,587,2525\nMANAGE_FIREWALL=1\nBLOCK_SMTP_EGRESS=1\nBLOCK_SMTP_FORWARD=1\n'
 # Writers call systemctl; stub successful install commands, Docker stays inactive.
 pre=pre.replace('systemctl() { return 1; }','systemctl() { if [[ "$*" == "start remnanode-firewall.service" ]]; then bash "$FIREWALL_SCRIPT"; else [[ "$*" != *docker.service* && "$*" != *is-active* ]]; fi; }')
 script=ROOT/'writer.sh';script.write_text(pre+B['functions'][name]+'\n'+name+'\n');run(['bash',str(script)])
 path=ROOT/({'write_firewall':'firewall','write_spamhaus_egress_guard':'SPAMHAUS_EGRESS_GUARD','write_outbound_ssh_guard':'OUTBOUND_SSH_GUARD','write_dns_reflection_guard':'DNS_REFLECTION_GUARD','write_bittorrent_guard':'BITTORRENT_GUARD'}[name]+'.sh')
 run(['bash','-n',str(path)])
 return pre,path
def activate(pre,path):run(['bash','-c',pre+'\nbash '+str(path)])
try:
 run(['ip','link','set','lo','up']);run(['sysctl','-qw','net.ipv4.ip_forward=1']);run(['sysctl','-qw','net.ipv6.conf.all.forwarding=1'])
 c=make_ns();s=make_ns();link(c,'ac','198.18.10','2001:db8:10::');link(s,'as','198.18.20','2001:db8:20::')
 for addr in ['198.18.20.3/32','198.18.20.200/32','8.8.8.8/32','203.0.113.53/32']:ns(s,['ip','addr','add',addr,'dev','lo'])
 ns(s,['ip','-6','addr','add','2001:db8:20::200/128','dev','lo','nodad']);run(['ip','-6','route','add','2001:db8:20::200/128','via','2001:db8:20::2'])
 for dst in ['8.8.8.8/32','203.0.113.53/32']:run(['ip','route','add',dst,'via','198.18.20.2'])
 ns(c,['ip','addr','add','198.18.10.3/32','dev','lo']);ns(c,['ip','-6','addr','add','2001:db8:10::3/128','dev','lo','nodad'])
 srv=ROOT/'server.py';srv.write_text('import socket\n'+B['server_source']+'\nserver()\n');sp=ns(s,['python3','-c','import subprocess;subprocess.Popen(["python3",'+repr(str(srv))+'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)'])
 threading.Thread(target=server,daemon=True).start();time.sleep(.2)
 result('baseline_v4',connect('198.18.20.2',443));result('baseline_v6',connect('2001:db8:20::2',443));result('baseline_spamhaus_v6_target',connect('2001:db8:20::200',443));result('baseline_dns_udp',connect('8.8.8.8',53,True))
 for name in ['write_firewall','write_outbound_ssh_guard','write_dns_reflection_guard','write_spamhaus_egress_guard','write_bittorrent_guard']:
  flush();pre,path=generate(name);activate(pre,path)
  result(name+'_syntax_and_apply',True)
  if name=='write_firewall':
   for dest,allow,deny in [('198.18.10.1','198.18.10.2','198.18.10.3'),('2001:db8:10::1','2001:db8:10::2','2001:db8:10::3')]:
    result('api_trusted_'+dest,client(c,dest,2222,source=allow));result('api_untrusted_'+dest,not client(c,dest,2222,source=deny))
   for dst in ['198.18.20.2','2001:db8:20::2']:
    for port in [25,465,587,2525]:result('smtp_output_'+dst+'_'+str(port),not connect(dst,port));result('smtp_forward_'+dst+'_'+str(port),not client(c,dst,port))
  elif name=='write_outbound_ssh_guard':
   result('ssh_block_unknown_v4',not connect('198.18.20.2',22));result('ssh_block_unknown_v6',not connect('2001:db8:20::2',22));result('ssh_forward_block',not client(c,'198.18.20.2',22))
   g={};exec(B['peers_source'].replace("if __name__ == '__main__':", "if False:"),g);g['refresh_peer_guard'](['198.18.20.2']);g['refresh_legacy'](['198.18.20.2'])
   result('ssh_forward_reply_source22',client(c,'198.18.20.2',443,source=['198.18.10.3',22]))
   result('ssh_allow_managed_peer',connect('198.18.20.2',22));result('ssh_deny_other_peer',not connect('198.18.20.3',22));result('ssh_forward_stays_blocked',not client(c,'198.18.20.2',22))
   peer_path=ROOT/'managed-peers';peer_path.write_text('8.8.8.8\n');g['PEERS']=peer_path;g['refresh_peer_guard'](['8.8.8.8']);g['refresh_legacy'](['8.8.8.8'])
   g['verify_runtime']();result('ssh_runtime_policy_verification',True)
   run(['nft','flush','chain','inet','remnanode_ssh_peers','output'])
   rejected=False
   try:g['verify_runtime']()
   except (ValueError,RuntimeError):rejected=True
   result('ssh_runtime_missing_rules_detected',rejected)
   with contextlib.redirect_stdout(io.StringIO()):g['refresh']()
  elif name=='write_dns_reflection_guard':
   for udp in [False,True]:result('dns_known_'+str(udp),connect('8.8.8.8',53,udp));result('dns_unknown_'+str(udp),not connect('203.0.113.53',53,udp));result('dns_forward_'+str(udp),not client(c,'8.8.8.8',53,udp))
   for udp in [False,True]:result('dns_known_v6_'+str(udp),connect('2001:db8:20::2',53,udp));result('dns_unknown_v6_'+str(udp),not connect('2001:db8:20::200',53,udp));result('dns_forward_v6_'+str(udp),not client(c,'2001:db8:20::2',53,udp))
  elif name=='write_spamhaus_egress_guard':
   result('spamhaus_ipv4_block',not connect('198.18.20.200',443));result('spamhaus_ipv6_block',not connect('2001:db8:20::200',443));result('spamhaus_forward_ipv4',not client(c,'198.18.20.200',443))
   before=run(['nft','-j','list','table','inet','remnanode_spamhaus_egress_guard']).stdout
   bad=pre+'\ncurl() { return 22; }; export -f curl; bash '+str(path);r=run(['bash','-c',bad],check=False)
   result('spamhaus_failed_fetch_keeps_rules',r.returncode!=0 and before==run(['nft','-j','list','table','inet','remnanode_spamhaus_egress_guard']).stdout)
   if B['version']!='4.1.6':
    run(['nft','delete','table','inet','remnanode_spamhaus_egress_guard']);r=run(['bash','-c',bad],check=False)
    result('spamhaus_boot_offline_restores_cache',r.returncode==0 and not connect('198.18.20.200',443) and not connect('2001:db8:20::200',443))
  else:
   for dst in ['198.18.20.2','2001:db8:20::2']:
    for port in [6881,6999,2710,6969,16881,51413,53442]:
     for udp in [False,True]:result('bt_port_'+dst+'_'+str(port)+'_'+str(udp),not connect(dst,port,udp));result('bt_forward_'+dst+'_'+str(port)+'_'+str(udp),not client(c,dst,port,udp))
  if name=='write_bittorrent_guard':
   for dst in ['198.18.20.2','2001:db8:20::2']:
    for udp in [False,True]:
     for sig in [b'\x13BitTorrent protocol',b'peer_id=',b'info_hash=',b'announce_peer',b'get_peers',b'find_node',b'd1:ad2:id20',b'.torrent']:
      result('bt_signature_'+dst+'_'+str(udp)+'_'+repr(sig),not connect_payload(dst,sig,udp))
     result('ordinary_payload_after_bt_'+dst+'_'+str(udp),connect_payload(dst,b'GET / HTTP/1.0\r\n\r\n',udp))
  result(name+'_ordinary_https_port',connect('198.18.20.2',443))
  if name!='write_spamhaus_egress_guard':
   source_port={'write_firewall':2525,'write_outbound_ssh_guard':22,'write_dns_reflection_guard':53,'write_bittorrent_guard':53442}[name]
   result(name+'_reply_to_client_source_port',client(c,'198.18.10.1',443,source=['198.18.10.2',source_port]))
   if name=='write_bittorrent_guard':result('bittorrent_udp_reply_to_client_source_port',client(c,'198.18.10.1',443,True,source=['198.18.10.2',53442]))
 print(json.dumps({'version':B['version'],'tests':len(rows),'passed':sum(r['passed'] for r in rows),'failures':[r for r in rows if not r['passed']],'checks':rows}))
finally:
 for pid in children:
  # Kill every process still in these own disposable namespaces.
  target=os.readlink('/proc/'+str(pid)+'/ns/net')
  for proc in pathlib.Path('/proc').iterdir():
   try:
    if proc.name.isdigit() and os.readlink(str(proc/'ns/net'))==target:os.kill(int(proc.name),signal.SIGKILL)
   except (FileNotFoundError,PermissionError,ProcessLookupError):pass
 shutil.rmtree(ROOT)
