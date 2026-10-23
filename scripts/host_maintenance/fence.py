"""Only local declared admission flags, owned TURN firewall table and fixed TLS probes."""
import http.client
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import time

from .collect import run
from .model import Deferred, atomic_json

MARKER = Path('/var/lib/honey-school-maintenance-admission/closed')
TABLE = 'honey_school_maintenance'
TABLE_COMMENT = 'honey-school-maintenance-owned'
CONTROL_PORTS = (3478,3479,3480,5349,5350,5351)
HOSTNAMES = {
    'ax41': ('online.honey.school','dev.online.honey.school'),
    'selectel': ('online.honeyschool.ru','dev.online.honeyschool.ru'),
}


def tls_status(hostname):
    connection = http.client.HTTPSConnection(hostname,context=ssl.create_default_context(),timeout=3)
    import socket
    connection._create_connection = lambda address,timeout,source_address=None:socket.create_connection(('127.0.0.1',443),timeout,source_address)
    try:
        connection.request('GET','/__honey_maintenance_probe__',headers={'Connection':'close'})
        response=connection.getresponse();response.read(8192)
        return response.status,response.getheader('X-Honey-Maintenance'),response.getheader('Retry-After')
    finally:connection.close()


class AdmissionFence:
    def __init__(self, owner, root):
        if owner not in HOSTNAMES:raise ValueError('unknown_owner')
        self.owner=owner
        self.record=Path(root)/'fence.json'

    def table(self):
        result=subprocess.run(['/usr/sbin/nft','-j','list','table','inet',TABLE],text=True,capture_output=True,check=False)
        if result.returncode:
            # A missing table is distinct from an inspection failure.
            all_tables=json.loads(run(['/usr/sbin/nft','-j','list','tables']))['nftables']
            if any(x.get('table',{}).get('name')==TABLE for x in all_tables):
                raise Deferred('fence_inspection_failed')
            return None
        rules=json.loads(result.stdout)['nftables']
        tables=[x['table'] for x in rules if 'table' in x]
        if len(tables)!=1 or tables[0].get('comment')!=TABLE_COMMENT:
            raise Deferred('fence_table_not_owned')
        return rules

    def nft_closed(self):
        rules=self.table()
        if rules is None:return False
        chains=[x['chain'] for x in rules if 'chain' in x]
        policy=next((c for c in chains if c['name']=='control_guard'),{})
        if policy.get('hook')!=('input' if self.owner=='selectel' else 'prerouting') or policy.get('prio')!=(-10 if self.owner=='selectel' else -110) or policy.get('policy')!='accept':
            return False
        expressions=[x['rule']['expr'] for x in rules if 'rule' in x]
        if len(expressions)!=3:return False
        # No broad table/chain discovery: only the exact local input control-port barrier.
        # nft may encode a scalar/set differently; normalize only the declared simple predicates.
        def predicate(expr):
            if len(expr)!=2:return None
            match=expr[0].get('match',{})
            return match.get('op'),match.get('left'),match.get('right'),expr[1]
        first=predicate(expressions[0])
        if first!=('==',{'meta':{'key':'iifname'}},'lo',{'return':None}):return False
        for expr,proto in zip(expressions[1:],('tcp','udp')):
            value=predicate(expr)
            if value is None or value[0]!='==' or value[1]!={'payload':{'protocol':proto,'field':'dport'}} or value[3]!={'drop':None}:return False
            if sorted(value[2].get('set',[]))!=list(CONTROL_PORTS if self.owner=='selectel' else CONTROL_PORTS):return False
        return True

    def install_nft(self):
        previous=self.table()
        ports=', '.join(str(p) for p in (CONTROL_PORTS if self.owner=='selectel' else CONTROL_PORTS))
        hook='input priority -10' if self.owner=='selectel' else 'prerouting priority -110'
        text=(f'delete table inet {TABLE}\n' if previous is not None else '')+f'''table inet {TABLE} {{
 comment "{TABLE_COMMENT}"
 chain control_guard {{
  type filter hook {hook}; policy accept;
  iifname "lo" return
  tcp dport {{ {ports} }} drop
  udp dport {{ {ports} }} drop
 }}
}}\n'''
        # One atomic transaction; never flush or replace another owner table.
        result=subprocess.run(['/usr/sbin/nft','-f','-'],input=text,text=True,capture_output=True,check=False)
        if result.returncode or not self.nft_closed():raise Deferred('turn_fence_failed')

    def closed(self):
        if not MARKER.is_file() or not self.record.is_file():return False
        if not self.nft_closed():return False
        try:return all(tls_status(hostname)==(503,'closed','60') for hostname in HOSTNAMES[self.owner])
        except (OSError,http.client.HTTPException):return False

    @contextmanager
    def exclusive(self):
        with self.record.with_suffix('.lock').open('a') as stream:
            try:fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError as error:raise Deferred('fence_busy') from error
            yield

    def close(self, lease_id, owner):
        with self.exclusive():return self._close(lease_id,owner)

    def _close(self, lease_id, owner):
        if not re.fullmatch('[0-9a-f]{32}',lease_id):raise Deferred('lease_request_invalid')
        if self.owner=='ax41':
            for row in run(['/usr/bin/ss','-H','-a','-t','-u','-n']).splitlines():
                fields=row.split()
                if len(fields)<6:raise Deferred('control_inventory_unknown')
                try:port=int(fields[4].rsplit(':',1)[1])
                except ValueError:continue
                if port in CONTROL_PORTS:raise Deferred('unowned_local_control_socket')
        # Refuse an unowned table or missing inspection authority before a public flag is created.
        self.table()
        old={}
        if self.record.exists():
            old=json.loads(self.record.read_text())
            if old.get('lease_id')!=lease_id:raise Deferred('fence_owned_by_other_lease')
        atomic_json(self.record,{'lease_id':lease_id,'owner':owner,'armed_at':old.get('armed_at',int(time.time())),'committed':old.get('committed',False)})
        with MARKER.open('w') as stream:
            os.fchmod(stream.fileno(),0o644)
            stream.flush();os.fsync(stream.fileno())
        directory=os.open(MARKER.parent,os.O_RDONLY)
        try:os.fsync(directory)
        finally:os.close(directory)
        self.install_nft()
        for hostname in HOSTNAMES[self.owner]:
            status,marker,retry=tls_status(hostname)
            if (status,marker,retry)!=(503,'closed','60'):raise Deferred('admission_route_not_fenced')
        return True

    def hold(self,lease_id):
        with self.exclusive():
            if not self.closed():raise Deferred('fence_not_closed')
            record=json.loads(self.record.read_text())
            if record.get('lease_id')!=lease_id:raise Deferred('fence_owned_by_other_lease')
            atomic_json(self.record,{**record,'committed':True})
        return True

    def expire_uncommitted(self,now):
        with self.exclusive():
            if not self.record.exists():return
            record=json.loads(self.record.read_text())
            if record.get('committed') is False and now-record['armed_at']>=60:
                self._open(record['lease_id'])

    def open(self,lease_id):
        with self.exclusive():return self._open(lease_id)

    def _open(self,lease_id):
        if not self.record.exists():
            if MARKER.exists() or self.table() is not None:raise Deferred('fence_journal_missing')
            return True
        if self.record.exists() and json.loads(self.record.read_text()).get('lease_id')!=lease_id:
            raise Deferred('fence_owned_by_other_lease')
        if self.table() is not None:
            run(['/usr/sbin/nft','delete','table','inet',TABLE])
        if MARKER.exists():MARKER.unlink()
        if self.record.exists():self.record.unlink()
        for parent in (MARKER.parent,self.record.parent):
            directory=os.open(parent,os.O_RDONLY)
            try:os.fsync(directory)
            finally:os.close(directory)
        return True

    def restore(self):
        with self.exclusive():
            if not self.record.exists():
                if MARKER.exists() or self.table() is not None:raise Deferred('fence_journal_missing')
                return
            record=json.loads(self.record.read_text())
            if not re.fullmatch('[0-9a-f]{32}',record.get('lease_id','')):raise Deferred('fence_journal_invalid')
            with MARKER.open('w') as stream:
                os.fchmod(stream.fileno(),0o644);stream.flush();os.fsync(stream.fileno())
            directory=os.open(MARKER.parent,os.O_RDONLY)
            try:os.fsync(directory)
            finally:os.close(directory)
            self.install_nft()
