"""Read-only migration evidence; row hashes and credentials never leave PROD."""
import base64,hmac,json,os,shlex,subprocess,sys
if os.uname().nodename.split(".")[0]!="playsay-prod":
 raise RuntimeError("production identity comparison requires playsay-prod")
SQL = 'SET TIME ZONE \'UTC\';\nSET datestyle = \'ISO, YMD\';\nSET intervalstyle = \'iso_8601\';\nSET extra_float_digits = 3;\nCREATE TEMP TABLE migration_digest (table_name text, row_count bigint, digest text);\nDO $compare$\nDECLARE item record;\nBEGIN\n  FOR item IN\n    SELECT n.nspname, c.relname\n    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace\n    WHERE n.nspname = \'public\' AND c.relkind IN (\'r\', \'p\')\n    ORDER BY c.relname COLLATE "C"\n  LOOP\n    EXECUTE format(\n      \'INSERT INTO migration_digest SELECT %L, count(*), md5(coalesce(string_agg(md5(row_to_json(x)::text), \'\'\'\' ORDER BY md5(row_to_json(x)::text) COLLATE "C"), \'\'\'\')) FROM %I.%I AS x\',\n      item.relname, item.nspname, item.relname\n    );\n  END LOOP;\nEND\n$compare$;\nSELECT json_build_object(\n  \'tables\', coalesce((SELECT json_object_agg(table_name, json_build_array(row_count, digest) ORDER BY table_name COLLATE "C") FROM migration_digest), \'{}\'::json),\n  \'schema\', (\n    SELECT md5(coalesce(string_agg(concat_ws(\'|\', c.relname, a.attname,\n      format_type(a.atttypid, a.atttypmod), a.attnotnull::text,\n      a.attidentity, a.attgenerated, coalesce(pg_get_expr(d.adbin, d.adrelid), \'\')),\n      E\'\\n\' ORDER BY c.relname COLLATE "C", a.attnum), \'\'))\n    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace\n    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped\n    LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum\n    WHERE n.nspname = \'public\' AND c.relkind IN (\'r\', \'p\')\n  ),\n  \'indexes\', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=\'public\' AND c.relkind IN (\'i\',\'I\')),\n  \'constraints\', (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname=\'public\')\n);\n'
base=['sudo','env','KUBECONFIG=/etc/rancher/k3s/k3s.yaml','kubectl']
def cmd(args,timeout=90):
 r=subprocess.run(base+args,text=True,capture_output=True,timeout=timeout)
 if r.returncode:raise RuntimeError('bounded PROD comparison failed; details suppressed')
 return r.stdout.strip()
def obj(args):return json.loads(cmd(args+['-o','json']))
state=obj(['-n','keycloak','get','statefulset','keycloak'])
if state.get('spec',{}).get('replicas')!=0 or state.get('status',{}).get('readyReplicas',0)!=0:
 raise RuntimeError('PROD Keycloak is not fully stopped')
pods=obj(['-n','keycloak','get','pods'])['items']
if any(any(o.get('kind')=='StatefulSet' and o.get('name')=='keycloak' for o in x['metadata'].get('ownerReferences',[])) for x in pods):
 raise RuntimeError('PROD Keycloak pod still exists')
source=[x for x in pods if x.get('status',{}).get('phase')=='Running' and any(c['name']=='postgresql' for c in x['spec']['containers'])]
if len(source)!=1:raise RuntimeError('source identity DB pod is not unique')
source=source[0]['metadata']['name']
cluster=obj(['-n','keycloak','get','cluster','keycloak-postgres-prod-import'])
if cluster.get('status',{}).get('readyInstances')!=1:raise RuntimeError('target identity DB is not ready')
target=cluster['status'].get('currentPrimary')
if not target:raise RuntimeError('target primary is unknown')
old_secret=obj(['-n','keycloak','get','secret','keycloak-postgresql'])
new_secret=obj(['-n','keycloak','get','secret','keycloak-postgres-prod-import-app'])
if new_secret.get('type')!='kubernetes.io/basic-auth':raise RuntimeError('target DB secret type mismatch')
if base64.b64decode(new_secret['data']['username'])!=b'bn_keycloak':raise RuntimeError('target DB owner mismatch')
if not hmac.compare_digest(old_secret['data']['password'],new_secret['data']['password']):raise RuntimeError('target DB password differs from source')

def old_psql(sql):
 shell='PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")" exec /opt/bitnami/postgresql/bin/psql -X -h 127.0.0.1 -U "$POSTGRES_USER" -d bitnami_keycloak -Atq -v ON_ERROR_STOP=1 -c '+shlex.quote(sql)
 return cmd(['-n','keycloak','exec',source,'-c','postgresql','--','sh','-lc',shell],timeout=180)
def new_psql(sql):
 return cmd(['-n','keycloak','exec',target,'-c','postgres','--','psql','-X','-U','postgres','-d','bitnami_keycloak','-Atq','-v','ON_ERROR_STOP=1','-c',sql],timeout=180)
active="SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND backend_type='client backend' AND pid<>pg_backend_pid();"
if old_psql(active)!='0':raise RuntimeError('source identity database still has client connections')
acl_sql="""SELECT json_build_object(
 'extraLoginRoles',(SELECT count(*) FROM pg_roles WHERE rolcanlogin AND rolname NOT LIKE 'pg_%' AND rolname NOT IN ('postgres','bn_keycloak')),
 'nonownerRelationGrants',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='public' AND a.grantee NOT IN (0,c.relowner)),
 'nonownerFunctionGrants',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(p.proacl) a WHERE n.nspname='public' AND a.grantee NOT IN (0,p.proowner)),
 'nonownerSchemaGrants',(SELECT count(*) FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='public' AND a.grantee NOT IN (0,n.nspowner)),
 'defaultAclOverrides',(SELECT count(*) FROM pg_default_acl));"""
acl_scope=json.loads(old_psql(acl_sql))
if any(value!=0 for value in acl_scope.values()):raise RuntimeError('source has additional DB roles or grants that require explicit migration')
metadata="SELECT json_build_object('version',current_setting('server_version'),'collation',d.datcollate,'ctype',d.datctype,'audit',current_setting('shared_preload_libraries'),'owner',pg_get_userbyid(d.datdba)) FROM pg_database d WHERE d.datname=current_database();"
# The retained source application owner cannot read superuser-only settings.
# Audit is a target gate; source version/locale/owner stay fully compared.
source_metadata=metadata.replace(",'audit',current_setting('shared_preload_libraries')", "")
old_metadata=json.loads(old_psql(source_metadata));new_metadata=json.loads(new_psql(metadata))
if not old_metadata['version'].startswith('17.4') or not new_metadata['version'].startswith('17.11'):
 raise RuntimeError('identity PostgreSQL versions differ from the reviewed migration')
if any(old_metadata[k]!=new_metadata[k] for k in ('collation','ctype','owner')) or 'pgaudit' not in new_metadata['audit']:
 raise RuntimeError('identity database locale, owner or audit setting changed')
definitions_sql="""SELECT json_build_object(
 'indexes',(SELECT coalesce(json_agg(json_build_array(tablename,indexname,indexdef) ORDER BY tablename COLLATE "C",indexname COLLATE "C"),'[]'::json) FROM pg_indexes WHERE schemaname='public'),
 'constraints',(SELECT coalesce(json_agg(json_build_array(c.relname,k.conname,pg_get_constraintdef(k.oid,true),k.convalidated) ORDER BY c.relname COLLATE "C",k.conname COLLATE "C"),'[]'::json) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'),
 'owners',(SELECT coalesce(json_agg(json_build_array(c.relname,c.relkind,pg_get_userbyid(c.relowner)) ORDER BY c.relname COLLATE "C"),'[]'::json) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','S','v','m')));"""
before=json.loads(old_psql(SQL));after=json.loads(new_psql(SQL))
old_definitions=json.loads(old_psql(definitions_sql));new_definitions=json.loads(new_psql(definitions_sql))
definitions_match={name:old_definitions[name]==new_definitions[name] for name in ('indexes','constraints','owners')}
if old_psql(active)!='0':raise RuntimeError('source identity database acquired another client during comparison')
different=sorted(set(before['tables'])^set(after['tables']) | {name for name in before['tables'].keys() & after['tables'].keys() if before['tables'][name]!=after['tables'][name]})
checks={'sourceVersion':old_metadata['version'],'targetVersion':new_metadata['version'],'localeOwnerAuditMatch':True,'extraSourceRolesAndGrants':acl_scope,'tableCount':len(before['tables']),'sourceRows':sum(v[0] for v in before['tables'].values()),'differentTables':different,'schemaMatches':before['schema']==after['schema'],'definitionsMatch':definitions_match,'indexCountMatches':before['indexes']==after['indexes'],'constraintCountMatches':before['constraints']==after['constraints'],'applicationPasswordMatches':True,'sourceClientConnectionsBeforeAndAfter':0}
print(json.dumps(checks,indent=2))
if different or not all(definitions_match.values()) or not checks['schemaMatches'] or not checks['indexCountMatches'] or not checks['constraintCountMatches']:
 raise SystemExit('source and target identity data/schema differ; do not switch Keycloak')
