"""Resolve/download/read signed APT candidates; unknown scripts/triggers deny installation."""
import hashlib
import io
import json
from pathlib import Path
import re
import shlex
import subprocess
import tarfile

from .collect import package_busy, run
from .model import Deferred

PACKAGE=re.compile(r'[a-z0-9][a-z0-9+.-]*(?::[a-z0-9]+)?')
SCRIPT_NAMES=frozenset(('preinst','postinst','prerm','postrm','config'))
SAFE_CONTROL_TRIGGERS=frozenset(('activate-noawait ldconfig','activate ldconfig'))
FORBIDDEN_PAYLOAD_PREFIXES=('/usr/local/','/etc/honeyschool/','/etc/honey-school-maintenance/','/var/lib/honeyschool/','/var/lib/honey-school-maintenance-admission/',
                            '/etc/nginx/','/etc/turnserver.conf','/etc/systemd/','/usr/lib/systemd/','/lib/systemd/',
                            '/etc/policy-rc.d','/etc/needrestart/','/etc/apt/','/etc/dpkg/')


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def candidate_rows(text):
    result=[]
    for line in text.splitlines():
        if line.startswith(('Remv ','Purg ')):raise Deferred('package_removal_not_allowed')
        if line.startswith('Inst '):
            match=re.fullmatch(r'Inst ([a-z0-9+.:_-]+)(?: \[([^\]]+)\])? \(([^ ]+) (.+)\)(?: \[[^\]]*\])?',line)
            if not match or not PACKAGE.fullmatch(match[1]) or not match[2]:raise Deferred('package_plan_unknown')
            # APT's signed origin assertion is supplemented by SHA256 from its candidate metadata.
            trusted=bool(re.search(r'Ubuntu:[^ ]*/(?:noble-security|noble-updates|noble)(?:/| |\])',match[4]))
            result.append({'name':match[1],'old_version':match[2],'version':match[3],'trusted_origin':trusted})
    return result


def control_files(archive):
    result=subprocess.run(['/usr/bin/dpkg-deb','--ctrl-tarfile',str(archive)],capture_output=True,check=False)
    if result.returncode or len(result.stdout)>8*1024*1024:raise Deferred('package_control_unavailable')
    files={}
    with tarfile.open(fileobj=io.BytesIO(result.stdout)) as data:
        for member in data:
            name=member.name.removeprefix('./')
            if member.isfile() and name in SCRIPT_NAMES|{'triggers'}:
                if member.size>256*1024:raise Deferred('package_control_oversized')
                files[name]=data.extractfile(member).read()
    return files


def installed_trigger_interests():
    rows=[]
    for line in Path('/var/lib/dpkg/triggers/File').read_text().splitlines():
        if not line or line.startswith('#'):continue
        fields=line.split()
        if len(fields)<2 or not fields[0].startswith('/'):raise Deferred('trigger_inventory_unknown')
        for owner in fields[1:]:
            owner=owner.removesuffix('/noawait')
            if not PACKAGE.fullmatch(owner):raise Deferred('trigger_inventory_unknown')
            rows.append((fields[0].rstrip('/'),owner))
    return rows


def audit_archive(archive,policy):
    files=control_files(archive)
    allowed=policy['maintainer_script_sha256']
    for name,body in files.items():
        if name in SCRIPT_NAMES and hashlib.sha256(body).hexdigest() not in allowed:
            raise Deferred('unsupported_package_hook')
        if name=='triggers':
            lines={line.strip() for line in body.decode('utf-8').splitlines() if line.strip() and not line.startswith('#')}
            if not lines<=SAFE_CONTROL_TRIGGERS:raise Deferred('unsupported_package_trigger')
            if lines:
                installed=Path('/var/lib/dpkg/info/libc-bin.postinst')
                if not installed.is_file() or digest(installed) not in policy['installed_trigger_sha256']:
                    raise Deferred('unsupported_installed_trigger')
    interests=installed_trigger_interests()
    process=subprocess.Popen(['/usr/bin/dpkg-deb','--fsys-tarfile',str(archive)],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    touched=set()
    try:
        with tarfile.open(fileobj=process.stdout,mode='r|') as data:
            for index,member in enumerate(data):
                if index>100000:raise Deferred('package_payload_oversized')
                name='/'+member.name.removeprefix('./').lstrip('/')
                if any(name==prefix.rstrip('/') or name.startswith(prefix) for prefix in FORBIDDEN_PAYLOAD_PREFIXES):
                    raise Deferred('protected_owner_payload')
                for prefix,owner in interests:
                    if name==prefix or name.startswith(prefix+'/'):touched.add(owner)
        if process.wait(timeout=20):raise Deferred('package_payload_unavailable')
    finally:
        if process.poll() is None:
            # This is a metadata reader, never apt/dpkg processing.
            process.terminate();process.wait(timeout=5)
    for owner in touched:
        script=Path('/var/lib/dpkg/info')/(owner+'.postinst')
        if not script.is_file() or digest(script) not in policy['installed_trigger_sha256']:
            raise Deferred('unsupported_installed_trigger')
    return True


def apt_hook_fingerprint():
    text=run(['/usr/bin/apt-config','dump'])
    values=[line for line in text.splitlines() if re.match(r'^(DPkg::(?:Pre-Invoke|Post-Invoke|Pre-Install-Pkgs)|APT::Update::Post-Invoke)',line)]
    return hashlib.sha256('\n'.join(values).encode()).hexdigest()


def apt_source_fingerprint():
    """Freeze reviewed source/key/config authority; Origin text alone is insufficient."""
    configuration=run(['/usr/bin/apt-config','dump'])
    if re.search(r'(?:AllowUnauthenticated|AllowInsecureRepositories|AllowDowngradeToInsecureRepositories|AllowWeakRepositories)\s+"(?:true|yes|on|1)"',configuration,re.I):raise Deferred('unsigned_package_source')
    files=[Path(name) for name in ('/etc/apt/sources.list','/etc/apt/trusted.gpg','/usr/lib/needrestart/apt-pinvoke','/usr/sbin/needrestart','/usr/sbin/dpkg-preconfigure','/usr/lib/update-notifier/update-motd-updates-available','/usr/bin/gdbus','/usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service','/usr/lib/packagekit/packagekitd')]
    for directory,patterns in [('/etc/apt/sources.list.d',('*.list','*.sources')),('/etc/apt/trusted.gpg.d',('*.gpg','*.asc')),('/etc/apt/keyrings',('*.gpg','*.asc')),('/usr/share/keyrings',('*.gpg','*.asc'))]:
        for pattern in patterns:files+=list(Path(directory).glob(pattern))
    rows=[configuration]
    for file in sorted(set(files)):
        if not file.exists():continue
        body=file.read_bytes()
        if len(body)>4*1024*1024:raise Deferred('package_source_inventory_unknown')
        if file.suffix in ('.list','.sources') or file.name=='sources.list':
            source=body.decode()
            authorities=re.findall(r'(?i)\bsigned-by=([^\]\s]+)',source)+re.findall(r'(?im)^Signed-By:\s*(/[^\n]+)$',source)
            for authority in authorities:
                for name in re.split(r'[,\s]+',authority):
                    if name.startswith('/') and Path(name) not in files:raise Deferred('package_key_inventory_unknown')
            if re.search(r'(?im)^\s*Trusted:\s*(?:yes|true|on|1)|\b(?:trusted|allow-insecure|allow-weak)\s*=\s*(?:yes|true|on|1)',source):raise Deferred('unsigned_package_source')
        rows.append(str(file)+':'+hashlib.sha256(body).hexdigest())
    return hashlib.sha256('\n'.join(rows).encode()).hexdigest()


def package_database_clean():
    if run(['/usr/bin/dpkg','--audit']).strip():raise Deferred('package_database_incomplete')
    pending=Path('/var/lib/dpkg/triggers/Unincorp')
    if pending.exists() and pending.read_text().strip():raise Deferred('package_triggers_pending')
    text=run(['/usr/bin/dpkg-query','-W','-f=${Package} ${Triggers-Pending} ${Triggers-Awaited}\\n'])
    if any(len(line.split())>1 for line in text.splitlines()):raise Deferred('package_triggers_pending')


class Planner:
    def __init__(self,root,policy):
        self.root=Path(root);self.policy=policy

    def plan(self):
        if package_busy():raise Deferred('package_lock_busy')
        package_database_clean()
        if apt_source_fingerprint()!=self.policy['apt_source_fingerprint']:raise Deferred('package_source_inventory_changed')
        if apt_hook_fingerprint()!=self.policy['apt_hook_fingerprint']:raise Deferred('apt_hook_inventory_changed')
        stamp=Path('/var/lib/apt/periodic/update-success-stamp')
        import time
        if not stamp.is_file() or not 0<=time.time()-stamp.stat().st_mtime<172800:raise Deferred('package_metadata_stale')
        text=run(['/usr/bin/apt-get','-s','-o','Debug::NoLocking=1','--no-remove','upgrade'],timeout=30)
        candidates=candidate_rows(text)
        allowed=[];blocked=[]
        download=self.root/'downloads'
        download.mkdir(mode=0o700,exist_ok=True)
        for item in candidates[:256]:
            try:
                name,version=item['name'],item['version']
                if not item['trusted_origin']:raise Deferred('package_origin_not_allowed')
                if name.split(':')[0] not in self.policy['package_names']:raise Deferred('package_not_reviewed')
                metadata=run(['/usr/bin/apt-cache','show',name+'='+version])
                sizes=re.findall(r'^Size: (\d+)$',metadata,re.M);hashes=re.findall(r'^SHA256: ([0-9a-f]{64})$',metadata,re.M)
                if len(set(hashes))!=1 or not sizes or max(map(int,sizes))>100*1024*1024:raise Deferred('package_metadata_unknown')
                uri=shlex.split(run(['/usr/bin/apt-get','--print-uris','download',name+'='+version]).strip())
                if len(uri)!=4 or not re.fullmatch(r'[a-zA-Z0-9+.%~:_-]+\.deb',uri[1]) or uri[3]!='SHA256:'+hashes[0]:raise Deferred('package_archive_identity_unknown')
                archive_name=uri[1]
                archive=download/(hashes[0]+'.deb')
                if not archive.exists():
                    # download is a separate non-disruptive stage; no installer or package hook runs.
                    result=subprocess.run(['/usr/bin/apt-get','download',name+'='+version],cwd=download,capture_output=True,timeout=90,check=False)
                    if result.returncode:raise Deferred('package_download_failed')
                    matches=[p for p in download.glob('*.deb') if p.name!=archive.name and digest(p)==hashes[0]]
                    if len(matches)!=1:raise Deferred('package_download_unknown')
                    matches[0].rename(archive)
                if archive.is_symlink() or digest(archive)!=hashes[0]:raise Deferred('package_integrity_failed')
                audit_archive(archive,self.policy)
                allowed.append({**item,'archive':str(archive),'sha256':hashes[0],'archive_name':archive_name})
            except Deferred as error:blocked.append({'name':item['name'],'reason':error.code})
        # Retain only dependency-closed reviewed subsets. One unrelated package
        # needing an unaudited dependency must not starve every eligible update.
        while allowed:
            expected={(x['name'],x['version']) for x in allowed}
            rejected=[]
            for item in allowed:
                specs=[item['name']+'='+item['version']]
                resolved=candidate_rows(run(['/usr/bin/apt-get','-s','--no-remove','--no-install-recommends',
                                             '--only-upgrade','install',*specs],timeout=30))
                if not all(x['trusted_origin'] for x in resolved) or not {(x['name'],x['version']) for x in resolved}<=expected:
                    rejected.append(item['name'])
            if not rejected:break
            blocked += [{'name':name,'reason':'package_dependency_not_reviewed'} for name in rejected]
            allowed=[x for x in allowed if x['name'] not in rejected]
        if allowed:
            resolved=resolve_batch(allowed)
            if {(x['name'],x['version']) for x in resolved}!={(x['name'],x['version']) for x in allowed}:
                raise Deferred('package_dependency_graph_changed')
        return {'allowed':allowed,'blocked':blocked,'pending_count':len(candidates)}


def resolve_batch(items):
    return candidate_rows(run(['/usr/bin/apt-get','-s','--no-remove','--no-install-recommends','--only-upgrade','install',
                               *[x['name']+'='+x['version'] for x in items]],timeout=30))


def installation_preflight(config,keys):
    """APT calls this while holding native frontend ownership, before its first dpkg.

    Subsequent invocations belong to the same already-started transaction and must
    finish configuring even after the time window closes. A crash never authorizes
    a different transaction to reuse the persisted permit.
    """
    from .model import atomic_json
    from .worker import Worker
    root=Path(config['state_dir']);state=json.loads((root/'worker.json').read_text())
    if state.get('phase') not in ('installing','overrun'):raise Deferred('transaction_not_owned')
    step=state['step_id'];permit=root/'transaction-permit.json'
    if permit.exists() and json.loads(permit.read_text()).get('step_id')==step:return
    package_database_clean()
    policy=json.loads(Path(config['package_policy']).read_text())
    if apt_source_fingerprint()!=policy['apt_source_fingerprint']:raise Deferred('package_source_inventory_changed')
    if apt_hook_fingerprint()!=policy['apt_hook_fingerprint']:raise Deferred('apt_hook_inventory_changed')
    plan=json.loads((root/'package-plan.json').read_text())
    for item in plan['allowed']:
        cached=root/'apt-archives'/item['archive_name']
        if cached.is_symlink() or not cached.is_file() or digest(cached)!=item['sha256']:raise Deferred('package_integrity_failed')
        if digest(item['archive'])!=item['sha256']:raise Deferred('package_integrity_failed')
        audit_archive(item['archive'],policy)
    resolved=resolve_batch(plan['allowed'])
    if not all(x['trusted_origin'] for x in resolved) or {(x['name'],x['version']) for x in resolved}!={(x['name'],x['version']) for x in plan['allowed']}:raise Deferred('package_dependency_graph_changed')
    owner=Worker(config,keys);owner.lease=state['lease_id']
    owner.request('/lease/preflight',step_id=step,operation='install')
    atomic_json(permit,{'step_id':step,'lease_id':state['lease_id']})
