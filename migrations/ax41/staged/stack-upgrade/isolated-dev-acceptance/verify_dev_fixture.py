"""Verify the exact DEV fixture before attaching a browser or port forward."""

import json
from pathlib import Path
import re
import shlex
import subprocess
import sys

import yaml

if len(sys.argv) != 2 or not re.fullmatch(r"[0-9a-f]{40}", sys.argv[1]):
    raise SystemExit("Usage: verify_dev_fixture.py <exact-develop-commit>")

root = Path(__file__).resolve().parent
repo = Path(subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10, check=True).stdout.strip())
app_path = repo / "argocd-apps/dev/apps/stack-candidate-acceptance.yaml"
files = [app_path] + [root / name for name in ("Chart.yaml", "values.yaml", "templates/fixture.yaml", "probe_inside_fixture.py", "verify_dev_fixture.py")]
for path in files:
    relative = path.relative_to(repo).as_posix()
    committed = subprocess.run(["git", "-C", str(repo), "show", sys.argv[1] + ":" + relative], capture_output=True, timeout=20, check=True).stdout
    if committed != path.read_bytes():
        raise SystemExit("Local fixture source does not match the exact develop commit")
application = yaml.safe_load(app_path.read_text())
values = application["spec"]["source"]["helm"]["valuesObject"]
if values.get("enabled") is not True or values.get("probeOnly") is not False or application["spec"]["destination"]["namespace"] != "playsay-dev":
    raise SystemExit("Source does not select the isolated DEV fixture")
render = subprocess.run(
    ["helm", "template", "acceptance", str(root), "-n", "playsay-dev", "-f", "-"],
    input=json.dumps(values), capture_output=True, text=True, timeout=30, check=True,
)
objects = [obj for obj in yaml.safe_load_all(render.stdout) if obj]
policy = next(obj for obj in objects if obj["kind"] == "NetworkPolicy")["spec"]
deployment = next(obj for obj in objects if obj["kind"] == "Deployment")["spec"]
payload = {"revision": sys.argv[1], "values": values, "policy": policy, "deployment": deployment, "probe": (root / "probe_inside_fixture.py").read_text()}

remote = r'''import json,subprocess,sys
item=json.load(sys.stdin)
b=["sudo","env","KUBECONFIG=/etc/rancher/k3s/k3s.yaml","kubectl"]
def get(*args):return json.loads(subprocess.run(b+list(args)+["-o","json"],capture_output=True,text=True,check=True,timeout=30).stdout)
root=get("-n","argocd","get","application","playsay-dev-root")
app=get("-n","argocd","get","application","stack-candidate-acceptance")
for a in (root,app):
 if a.get("status",{}).get("sync",{}).get("status")!="Synced" or a["status"]["sync"].get("revision")!=item["revision"]:raise RuntimeError("Argo revision mismatch")
s=app["spec"]
if s["destination"].get("namespace")!="playsay-dev" or s["source"].get("targetRevision")!="develop" or s["source"].get("path")!="migrations/ax41/staged/stack-upgrade/isolated-dev-acceptance" or s["source"].get("helm",{}).get("valuesObject")!=item["values"]:raise RuntimeError("Unexpected fixture application")
policy=get("-n","playsay-dev","get","networkpolicy","stack-candidate-acceptance")["spec"]
for key in ("podSelector","egress","policyTypes"):
 if policy.get(key)!=item["policy"].get(key):raise RuntimeError("Fixture policy mismatch")
if policy.get("ingress",[])!=[]:raise RuntimeError("Unexpected fixture ingress")
d=get("-n","playsay-dev","get","deployment","stack-candidate-acceptance")
status=d.get("status",{});generation=d["metadata"]["generation"]
if d["spec"].get("replicas",1)!=1 or status.get("observedGeneration",0)<generation or status.get("updatedReplicas",0)!=1 or status.get("readyReplicas",0)!=1 or status.get("availableReplicas",0)!=1:raise RuntimeError("Fixture deployment is not ready")
pods=get("-n","playsay-dev","get","pods","-l","app=stack-candidate-acceptance")["items"]
pods=[p for p in pods if not p["metadata"].get("deletionTimestamp")]
if len(pods)!=1:raise RuntimeError("Unexpected fixture pod count")
p=pods[0];meta=p["metadata"];spec=p["spec"]
if spec.get("automountServiceAccountToken") is not False or spec.get("hostNetwork",False) or spec.get("volumes"):raise RuntimeError("Unexpected fixture pod access")
owners=[x for x in meta.get("ownerReferences",[]) if x.get("kind")=="ReplicaSet" and x.get("controller")]
if len(owners)!=1:raise RuntimeError("Unexpected pod owner")
rs=get("-n","playsay-dev","get","replicaset",owners[0]["name"])
if rs["metadata"]["uid"]!=owners[0]["uid"] or not any(x.get("kind")=="Deployment" and x.get("uid")==d["metadata"]["uid"] for x in rs["metadata"].get("ownerReferences",[])):raise RuntimeError("Fixture owner mismatch")
expected={x["name"]:x for x in item["deployment"]["template"]["spec"]["containers"]}
actual={x["name"]:x for x in spec.get("containers",[])}
states={x["name"]:x for x in p.get("status",{}).get("containerStatuses",[])}
if set(actual)!=set(expected) or set(states)!=set(expected):raise RuntimeError("Unexpected fixture containers")
for name in expected:
 if actual[name].get("image")!=expected[name]["image"] or actual[name].get("env",[])!=expected[name].get("env",[]):raise RuntimeError("Fixture image or environment mismatch")
 if not states[name].get("ready") or expected[name]["image"].split("@",1)[1] not in states[name].get("imageID",""):raise RuntimeError("Fixture container digest is not ready")
labels=meta.get("labels",{})
def matches(selector):
 for k,v in selector.get("matchLabels",{}).items():
  if labels.get(k)!=v:return False
 for e in selector.get("matchExpressions",[]):
  k=e["key"];op=e["operator"];vals=e.get("values",[])
  if op=="In" and labels.get(k) not in vals:return False
  if op=="NotIn" and k in labels and labels[k] in vals:return False
  if op=="Exists" and k not in labels:return False
  if op=="DoesNotExist" and k in labels:return False
  if op not in ("In","NotIn","Exists","DoesNotExist"):raise RuntimeError("Unknown policy selector")
 return True
policies=get("-n","playsay-dev","get","networkpolicies")["items"]
if [x["metadata"]["name"] for x in policies if matches(x.get("spec",{}).get("podSelector",{}))]!=["stack-candidate-acceptance"]:raise RuntimeError("Additional policy may weaken isolation")
for ns,name in (("playsay-data","playsay-postgres-rw"),("playsay-dev","collaboration-service")):
 if not any(x.get("addresses") for x in get("-n",ns,"get","endpoints",name).get("subsets",[])):raise RuntimeError("Shared service has no ready endpoint")
sql="SELECT CASE WHEN current_database()='playsay' AND to_regclass('public.lesson') IS NOT NULL AND to_regclass('public.app_user') IS NOT NULL AND to_regclass('public.lesson_material') IS NOT NULL THEN 'ready' ELSE 'missing' END"
query=subprocess.run(b+["-n","playsay-dev","exec",meta["name"],"-c","postgres","--","psql","-X","-h","127.0.0.1","-U","postgres","-d","playsay","-Atqc",sql],capture_output=True,text=True,timeout=20)
if query.returncode or query.stdout.strip()!="ready":raise RuntimeError("Synthetic database schema is not ready")
probe=subprocess.run(b+["-n","playsay-dev","exec","-i",meta["name"],"-c","postgres","--","python3","-"],input=item["probe"],capture_output=True,text=True,timeout=30)
if probe.returncode or json.loads(probe.stdout)!={"devIdentity":"reachable","sharedDatabase":"unreachable","sharedCollaboration":"unreachable"}:raise RuntimeError("Fixture network boundary failed")
again=get("-n","playsay-dev","get","pod",meta["name"])
if again["metadata"].get("uid")!=meta["uid"]:raise RuntimeError("Fixture changed during observation")
print(json.dumps({"revision":item["revision"],"podName":meta["name"],"podUid":meta["uid"],"imagesVerified":True,"syntheticDatabase":True,"networkBoundaryVerified":True}))
'''
identity = "/Users/evgeniymednov/.ssh/play_and_say_vps_ed25519"
proxy = f"ssh -i {identity} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -W %h:%p root@65.109.55.110"
command = ["ssh", "-i", identity, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", f"ProxyCommand={proxy}", "playsay@10.60.0.30", "python3 -c " + shlex.quote(remote)]
result = subprocess.run(command, input=json.dumps(payload), capture_output=True, text=True, timeout=150)
if result.returncode:
    raise SystemExit("DEV fixture verification failed; inspect sanitized cluster state and do not attach a browser")
print(result.stdout, end="")
