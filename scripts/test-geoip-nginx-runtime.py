#!/usr/bin/env python3
"""Exercise checked-in nginx navigation policy in an isolated loopback process.

Run locally with nginx installed, or pass --ssh-key to use the established RF edge.
Country classification is synthetic; this does not validate the IPinfo dataset.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

RUNNER = r'''
import http.client,json,socket,subprocess,sys,tempfile,time
from pathlib import Path
data=json.load(sys.stdin)
with tempfile.TemporaryDirectory(prefix="geoip-policy-probe-") as directory:
 root=Path(directory)
 with socket.socket() as reserve:
  reserve.bind(("127.0.0.1",0));port=reserve.getsockname()[1]
 config="pid "+str(root/"nginx.pid")+"; error_log "+str(root/"error.log")+" error; events {} http { access_log off; "
 config+='map $remote_addr $honey_school_geo_country_code { default ""; 127.0.0.1 RU; 127.0.0.2 RU; 127.0.0.3 US; ::1 RU; }\n'
 config+=data['policy']
 config+='server { listen 127.0.0.1:'+str(port)+'; listen [::1]:'+str(port)+'; server_name _; location / {'+data['snippet']+' add_header X-Test-Client $honey_school_client_ip always; add_header X-Test-Peer $remote_addr always; return 204; } } }'
 target=root/'nginx.conf';target.write_text(config)
 subprocess.run(['nginx','-t','-p',directory+'/', '-c',str(target)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 process=subprocess.Popen(['nginx','-p',directory+'/', '-c',str(target),'-g','daemon off;'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  for _ in range(50):
   try:
    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
   except OSError:time.sleep(.02)
  cases=[
   ('RU cold HTML',302,{}),
   ('RU explicit navigation',302,{'headers':{'Sec-Fetch-Mode':'navigate'}}),
   ('RU IPv6',302,{'destination':'::1','source':'::1'}),
   ('non RU',204,{'source':'127.0.0.3'}),
   ('unknown country',204,{'source':'127.0.0.4'}),
   ('trusted RF peer with school upstream host',204,{'source':'127.0.0.2'}),
   ('trusted RF normalized browser address',204,{'source':'127.0.0.2','headers':{'X-Real-IP':'2001:db8::5','X-Forwarded-For':'198.51.100.9'},'client':'2001:db8::5'}),
   ('spoofed client headers do not suppress direct RU',302,{'headers':{'X-Real-IP':'127.0.0.3','X-Forwarded-For':'127.0.0.3'}}),
   ('spoofed RU headers do not redirect non RU',204,{'source':'127.0.0.3','headers':{'X-Real-IP':'127.0.0.1','X-Forwarded-For':'127.0.0.1'}}),
   ('production flag off',204,{'host':'online.honey.school'}),
   ('ops excluded',204,{'host':'ops.honey.school'}),
   ('RF host excluded',204,{'host':'dev.online.honeyschool.ru'}),
   ('POST excluded',204,{'method':'POST'}),
   ('asset excluded',204,{'headers':{'Accept':'application/javascript'},'path':'/assets/app.js'}),
   ('API excluded',204,{'path':'/api/profile'}),
   ('auth excluded',204,{'path':'/auth/callback?code=synthetic'}),
   ('signaling excluded',204,{'path':'/livekit/rtc'}),
   ('collaboration excluded',204,{'path':'/collab/ws'}),
   ('upgrade excluded',204,{'headers':{'Upgrade':'websocket'}}),
  ]
  for label,expected,options in cases:
   headers={'Host':options.get('host','dev.online.honey.school'),'Accept':'text/html',**options.get('headers',{})}
   connection=http.client.HTTPConnection(options.get('destination','127.0.0.1'),port,timeout=3,source_address=(options.get('source','127.0.0.1'),0))
   path=options.get('path','/lessons?tab=next')
   connection.request(options.get('method','GET'),path,headers=headers)
   response=connection.getresponse();response.read()
   assert response.status==expected,label
   if expected!=302:
    assert response.getheader('X-Test-Peer')==options.get('source','127.0.0.1'),label
    assert response.getheader('X-Test-Client')==options.get('client',options.get('source','127.0.0.1')),label
   if expected==302:
    assert response.getheader('Location')=='https://dev.online.honeyschool.ru'+path,label
    assert response.getheader('Cache-Control')=='private, no-store',label
    assert response.getheader('Vary')=='Sec-Fetch-Mode, Accept',label
   connection.close()
  print('PASS real nginx policy: '+str(len(cases))+' navigation, spoofing, environment, cache and loop cases')
 finally:
  process.terminate()
  try:process.wait(timeout=3)
  except subprocess.TimeoutExpired:process.kill();process.wait()
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssh-key")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    policy = (root / "ansible/roles/edge-proxy/templates/playsay-honey.conf.j2").read_text()
    policy = policy.split("limit_req_zone", 1)[0]
    policy = policy.replace("{{ 1 if honey_school_geoip_redirect_prod_enabled | bool else 0 }}", "0")
    policy = policy.replace("{{ 1 if honey_school_geoip_redirect_dev_enabled | bool else 0 }}", "1")
    policy = re.sub(r"{% for trusted_address.*?{% endfor %}", "127.0.0.2 0;", policy, flags=re.S)
    tasks = (root / "ansible/roles/honey-school-geoip/tasks/main.yaml").read_text()
    snippet = tasks.split("- name: Install the browser-entry redirect snippet", 1)[1].split("    content: |\n", 1)[1].split("  notify:", 1)[0]
    snippet = "\n".join(line[6:] for line in snippet.splitlines())
    assert "{{" not in policy and "return 302" in snippet
    command = ["python3", "-c", RUNNER]
    if args.ssh_key:
        import shlex
        command = ["ssh", "-o", "BatchMode=yes", "-i", args.ssh_key, "root@94.102.89.213",
                   "python3 -c " + shlex.quote(RUNNER)]
    subprocess.run(command, input=json.dumps({"policy": policy, "snippet": snippet}).encode(), check=True)


if __name__ == "__main__":
    main()
