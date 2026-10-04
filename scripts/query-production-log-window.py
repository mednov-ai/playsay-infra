#!/usr/bin/env python3
"""Read a bounded exact window via the VPN-protected operator route; print aggregates only."""
import argparse
import collections
import datetime as dt
import json
import re
import subprocess

SOURCES=('rf_nginx','ax41_nginx','rf_coturn','livekit','api_route','collaboration')
def timestamp(value):
    result=dt.datetime.fromisoformat(value.replace('Z','+00:00'))
    if result.tzinfo is None: raise ValueError('explicit timezone required')
    return result.astimezone(dt.timezone.utc).isoformat().replace('+00:00','Z')

def report(records):
    counts=collections.Counter(); hearts=collections.Counter(); bad_inputs=collections.Counter(); ids=set(); requests=collections.defaultdict(set)
    for row in records:
        source=row.get('source'); event=row.get('event'); event_id=row.get('event_id','')
        if source not in SOURCES or not re.fullmatch(r'[a-f0-9-]{36}',event_id) or event_id in ids: continue
        ids.add(event_id)
        if event=='collector_heartbeat':
            if str(row.get('input_ok',0)) == '1': hearts[source]+=1
            else: bad_inputs[source]+=1
        else: counts[source]+=1
        req=row.get('request_id','')
        if source in ('rf_nginx','ax41_nginx') and re.fullmatch(r'[a-f0-9]{32}',req): requests[req].add(source)
    return {'coverage':{source:{'events':counts[source],'heartbeats':hearts[source],'state':'input_unavailable' if bad_inputs[source] else 'events_present' if counts[source] else 'healthy_silence' if hearts[source] else 'missing_telemetry'} for source in SOURCES}, 'paired_signaling_requests':sum(len(sources)==2 for sources in requests.values()), 'unique_events':len(ids), 'attribution':'TCP/HTTPS success does not establish UDP media availability or a failing provider/hop; correlate existing path and media metrics for the same interval.'}

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--start',required=True); parser.add_argument('--end',required=True); parser.add_argument('--curl-config',required=True); args=parser.parse_args()
    start,end=timestamp(args.start),timestamp(args.end)
    if start>=end or dt.datetime.fromisoformat(end.replace('Z','+00:00'))-dt.datetime.fromisoformat(start.replace('Z','+00:00'))>dt.timedelta(hours=2): raise SystemExit('window must be positive and at most two hours')
    result=subprocess.run(['curl','--config',args.curl_config,'--proto','=https','--no-insecure','--no-location','--silent','--fail','--max-time','30','--max-filesize','4194304','--url','https://ops.honey.school/victoria-logs/select/logsql/query','--data-urlencode','query=environment:prod','--data-urlencode','start='+start,'--data-urlencode','end='+end,'--data-urlencode','limit=10000'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=32)
    if result.returncode: raise SystemExit('protected log query failed')
    rows=[json.loads(line) for line in result.stdout.splitlines() if line]
    output=report(rows); output.update(start=start,end=end,truncated=len(rows)>=10000)
    print(json.dumps(output,indent=2))

if __name__=='__main__': main()
