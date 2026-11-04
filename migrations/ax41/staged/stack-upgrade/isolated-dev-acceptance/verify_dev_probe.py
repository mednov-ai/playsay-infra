"""Verify the exact GitOps probe and run its read-only connectivity check."""

import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

import yaml

if len(sys.argv) != 2 or not re.fullmatch(r"[0-9a-f]{40}", sys.argv[1]):
    raise SystemExit("Usage: verify_dev_probe.py <exact-develop-commit>")

root = Path(__file__).resolve().parent
repository = Path(subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10, check=True).stdout.strip())
for name in ("Chart.yaml", "values.yaml", "templates/fixture.yaml", "probe_inside_fixture.py", "verify_dev_probe.py"):
    path = root / name
    relative = path.relative_to(repository).as_posix()
    source = subprocess.run(["git", "-C", str(repository), "show", sys.argv[1] + ":" + relative], capture_output=True, timeout=20, check=True).stdout
    if source != path.read_bytes():
        raise SystemExit("Local probe source does not match the exact develop commit")
render = subprocess.run(
    ["helm", "template", "acceptance", str(root), "-n", "playsay-dev", "--set", "enabled=true", "--set", "probeOnly=true"],
    capture_output=True, text=True, timeout=30, check=True,
)
objects = [obj for obj in yaml.safe_load_all(render.stdout) if obj]
expected_policy = next(obj for obj in objects if obj["kind"] == "NetworkPolicy")["spec"]
payload = {
    "revision": sys.argv[1],
    "policy": expected_policy,
    "probe": (root / "probe_inside_fixture.py").read_text(),
}

remote = r'''import json,subprocess,sys
item=json.load(sys.stdin)
base=["sudo","env","KUBECONFIG=/etc/rancher/k3s/k3s.yaml","kubectl"]
def get(*args):
 return json.loads(subprocess.run(base+list(args)+["-o","json"],capture_output=True,text=True,check=True,timeout=30).stdout)
root=get("-n","argocd","get","application","playsay-dev-root")
app=get("-n","argocd","get","application","stack-candidate-acceptance")
for a in (root,app):
 if a.get("status",{}).get("sync",{}).get("status")!="Synced" or a["status"]["sync"].get("revision")!=item["revision"]: raise RuntimeError("Argo revision is not the expected synchronized revision")
s=app["spec"]
if s["destination"].get("namespace")!="playsay-dev" or s["source"].get("targetRevision")!="develop" or s["source"].get("path")!="migrations/ax41/staged/stack-upgrade/isolated-dev-acceptance" or s["source"].get("helm",{}).get("valuesObject")!={"enabled":True,"probeOnly":True}: raise RuntimeError("Unexpected DEV Argo application configuration")
policy=get("-n","playsay-dev","get","networkpolicy","stack-candidate-acceptance")
actual=policy["spec"]
for name in ("podSelector","egress","policyTypes"):
 if actual.get(name)!=item["policy"].get(name): raise RuntimeError("Network policy does not match reviewed source")
if actual.get("ingress",[])!=[]:raise RuntimeError("Unexpected fixture ingress")
job=get("-n","playsay-dev","get","job","stack-candidate-acceptance-network-probe")
if job["spec"].get("activeDeadlineSeconds")!=7200:raise RuntimeError("Unexpected probe deadline")
pods=get("-n","playsay-dev","get","pods","-l","job-name=stack-candidate-acceptance-network-probe")["items"]
pods=[p for p in pods if not p["metadata"].get("deletionTimestamp")]
if len(pods)!=1:raise RuntimeError("Unexpected active probe count")
p=pods[0];meta=p["metadata"];spec=p["spec"]
if not any(o.get("kind")=="Job" and o.get("name")==job["metadata"]["name"] and o.get("uid")==job["metadata"]["uid"] for o in meta.get("ownerReferences",[])):raise RuntimeError("Probe ownership mismatch")
if meta.get("labels",{}).get("app")!="stack-candidate-acceptance" or spec.get("automountServiceAccountToken") is not False or len(spec.get("containers",[]))!=1:raise RuntimeError("Unexpected probe pod")
c=spec["containers"][0]
if c.get("name")!="probe" or c.get("image")!="ghcr.io/cloudnative-pg/postgresql@sha256:03a1c6a62b27e8ad31cae5c085131b5ac706b09403d6fcb6c58d16c8daa257cd" or c.get("env") or c.get("envFrom"):raise RuntimeError("Unexpected probe image or secrets")
if p.get("status",{}).get("phase")!="Running" or not any(x.get("type")=="Ready" and x.get("status")=="True" for x in p.get("status",{}).get("conditions",[])):raise RuntimeError("Probe is not ready")
labels=meta.get("labels",{})
def matches(selector):
 for k,v in selector.get("matchLabels",{}).items():
  if labels.get(k)!=v:return False
 for e in selector.get("matchExpressions",[]):
  k=e["key"]; op=e["operator"]; vals=e.get("values",[])
  if op=="In" and labels.get(k) not in vals:return False
  if op=="NotIn" and k in labels and labels[k] in vals:return False
  if op=="Exists" and k not in labels:return False
  if op=="DoesNotExist" and k in labels:return False
  if op not in ("In","NotIn","Exists","DoesNotExist"):raise RuntimeError("Unknown selector operator")
 return True
policies=get("-n","playsay-dev","get","networkpolicies")["items"]
matching=[x["metadata"]["name"] for x in policies if matches(x.get("spec",{}).get("podSelector",{}))]
if matching!=["stack-candidate-acceptance"]:raise RuntimeError("Additional policy may weaken isolation")
for ns,name in (("playsay-data","playsay-postgres-rw"),("playsay-dev","collaboration-service")):
 endpoints=get("-n",ns,"get","endpoints",name)
 if not any(x.get("addresses") for x in endpoints.get("subsets",[])):raise RuntimeError("A shared DEV service has no ready endpoint")
cluster=get("-n","playsay-data","get","clusters.postgresql.cnpg.io","playsay-postgres")
primary=cluster.get("status",{}).get("currentPrimary","")
if not primary.startswith("playsay-postgres-") or not primary.rsplit("-",1)[-1].isdigit():raise RuntimeError("Unknown DEV database primary")
r=subprocess.run(base+["-n","playsay-data","exec",primary,"-c","postgres","--","pg_isready","-h","127.0.0.1","-p","5432"],capture_output=True,text=True,timeout=20)
if r.returncode:raise RuntimeError("Shared DEV database is not ready")
probe=subprocess.run(base+["-n","playsay-dev","exec","-i",meta["name"],"-c","probe","--","python3","-"],input=item["probe"],capture_output=True,text=True,timeout=30)
if probe.returncode:raise RuntimeError("The probe did not establish the required network boundary")
report=json.loads(probe.stdout)
if report!={"devIdentity":"reachable","sharedDatabase":"unreachable","sharedCollaboration":"unreachable"}:raise RuntimeError("Unexpected probe output")
again=get("-n","playsay-dev","get","pod",meta["name"])
if again["metadata"].get("uid")!=meta["uid"]:raise RuntimeError("Probe changed during observation")
print(json.dumps({"revision":item["revision"],"probeUid":meta["uid"],"networkBoundary":report,"sharedServicesReady":True}))
'''

identity = "/Users/evgeniymednov/.ssh/play_and_say_vps_ed25519"
proxy = f"ssh -i {identity} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -W %h:%p root@65.109.55.110"
command = [
    "ssh", "-i", identity, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
    "-o", f"ProxyCommand={proxy}", "playsay@10.60.0.30", "python3 -c " + shlex.quote(remote),
]
result = subprocess.run(command, input=json.dumps(payload), capture_output=True, text=True, timeout=150)
if result.returncode:
    raise SystemExit("DEV probe verification failed; retain the fixture and inspect sanitized cluster state")
print(result.stdout, end="")
