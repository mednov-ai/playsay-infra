#!/usr/bin/env python3
"""Execute certificate PromQL alert fixtures using an external promtool binary."""
import argparse
import copy
from pathlib import Path
import subprocess
import tempfile
import yaml

ROOT=Path(__file__).resolve().parents[2]
BASE={'owner':'ax41','lineage':'online.honey.school','certificate_environment':'shared','activation':'nginx'}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--promtool',required=True);args=parser.parse_args()
    output=subprocess.check_output(['helm','template','monitoring-lite',str(ROOT/'helm-charts/monitoring-lite'),'-f',str(ROOT/'helm-charts/monitoring-lite/values-prod.yaml')],text=True)
    config=next(doc for doc in yaml.safe_load_all(output) if doc and doc.get('kind')=='ConfigMap' and 'certificates.yaml' in doc.get('data',{}))
    full=yaml.safe_load(config['data']['certificates.yaml'])
    fixture=copy.deepcopy(full)
    fixture['groups'][0]['rules']=[r for r in fixture['groups'][0]['rules'] if 'record' not in r or r['labels']==BASE]
    alerts={r['alert']:r for r in fixture['groups'][0]['rules'] if 'alert' in r}
    tests=[]
    def case(alert,fields,minutes=1,severity='critical',labels=None,resolved=False):
        labels=labels or BASE
        suffix='{'+','.join('%s="%s"'%x for x in labels.items())+'}'
        series=[{'series':name+suffix,'values':str(value)+'+0x'+str(minutes+2)} for name,value in fields.items()]
        tests.append({'interval':'1m','input_series':series,'alert_rule_test':[{'eval_time':str(minutes)+'m','alertname':alert,
            'exp_alerts':[] if resolved else [{'exp_labels':{**labels,'severity':severity},'exp_annotations':alerts[alert]['annotations']}]}]})
    case('HoneySchoolCertificateInventoryGap',{})
    case('HoneySchoolCertificateHealthStale',{'hs_certificate_health_checked_at':1},121)
    case('HoneySchoolCertificateInvalid',{'hs_certificate_health_healthy':0})
    case('HoneySchoolCertificateExpiring',{'hs_certificate_health_served_expiry':29*86400},severity='warning')
    case('HoneySchoolCertificateExpiring',{'hs_certificate_health_served_expiry':31*86400},resolved=True)
    case('HoneySchoolCertificateExpiryCritical',{'hs_certificate_health_disk_expiry':13*86400})
    case('HoneySchoolCertificateExpiryCritical',{'hs_certificate_health_disk_expiry':15*86400},resolved=True)
    case('HoneySchoolCertificateActivationMismatch',{'hs_certificate_health_mismatch_since':1},16)
    case('HoneySchoolCertificateActivationFailed',{'hs_certificate_renewal_activation_success':0})
    case('HoneySchoolTurnCertificateActivationPending',{'hs_certificate_health_pending_since':1},61,severity='warning',
         labels={'owner':'selectel','lineage':'turn.honeyschool.ru','certificate_environment':'prod','activation':'deferred-turn'})
    case('HoneySchoolCertificateRenewalFailed',{'hs_certificate_renewal_success':0,'hs_certificate_renewal_checked_at':1},severity='warning')
    case('HoneySchoolCertificateRenewalFailurePersistent',{'hs_certificate_renewal_failure_since':1},1441)
    case('HoneySchoolCertificateRenewalStale',{'hs_certificate_renewal_checked_at':1},1561)
    case('HoneySchoolCertificateRehearsalStale',{'hs_certificate_rehearsal_checked_at':1},11521)
    case('HoneySchoolCertificateRehearsalMissing',{})
    case('HoneySchoolCertificateHealthStale',{'hs_certificate_health_checked_at':1},119,resolved=True)
    # Explicit transition: the same alert fires, then resolves on fresh healthy data.
    suffix='{'+','.join('%s="%s"'%x for x in BASE.items())+'}'
    tests.append({'interval':'1m','input_series':[{'series':'hs_certificate_health_healthy'+suffix,'values':'0 1 1'}],
        'alert_rule_test':[{'eval_time':'0m','alertname':'HoneySchoolCertificateInvalid','exp_alerts':[{'exp_labels':{**BASE,'severity':'critical'},'exp_annotations':alerts['HoneySchoolCertificateInvalid']['annotations']}]},
                           {'eval_time':'2m','alertname':'HoneySchoolCertificateInvalid','exp_alerts':[]}]})
    with tempfile.TemporaryDirectory(prefix='hs-alert-fixtures-') as directory:
        path=Path(directory);(path/'full.yaml').write_text(yaml.safe_dump(full));(path/'rules.yaml').write_text(yaml.safe_dump(fixture))
        (path/'tests.yaml').write_text(yaml.safe_dump({'rule_files':['rules.yaml'],'evaluation_interval':'1m','tests':tests}))
        subprocess.run([args.promtool,'check','rules',str(path/'full.yaml')],check=True)
        subprocess.run([args.promtool,'test','rules',str(path/'tests.yaml')],cwd=path,check=True)
    print('certificate_alert_fixtures_passed cases='+str(len(tests)))

if __name__=='__main__':main()
