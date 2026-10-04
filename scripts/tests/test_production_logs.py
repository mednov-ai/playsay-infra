import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('collector', ROOT / 'ansible/roles/production-log-collector/files/collector.py')
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)

class LogsTest(unittest.TestCase):
    def test_sources_and_privacy(self):
        fixtures = json.loads((ROOT/'scripts/tests/fixtures/production-log-source-examples.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            box = c.Outbox(directory)
            for fixture in fixtures:
                source = fixture['source']; raw = fixture['input']
                if isinstance(raw, dict): raw = dict(raw, MESSAGE=raw['MESSAGE']+' token=CANARY_SECRET room=PRIVATE_USER')
                else: raw += ' token=CANARY_SECRET room=PRIVATE_USER uri=/lesson?token=CANARY_SECRET'
                event = c.sanitize(source, raw)
                self.assertIsNotNone(event, source)
                self.assertNotIn('CANARY_SECRET', json.dumps(event)); self.assertNotIn('PRIVATE_USER', json.dumps(event))
                self.assertTrue(event['timestamp'].endswith('Z')); box.enqueue(source, event)
            box.db.close()
            contents = b''.join(p.read_bytes() for p in Path(directory).iterdir())
            self.assertNotIn(b'CANARY_SECRET', contents); self.assertNotIn(b'PRIVATE_USER', contents)

    def test_unknown_invalid_and_forbidden_values(self):
        for source in c.SOURCES:
            self.assertIsNone(c.sanitize(source, 'CANARY_SECRET random unrecognized payload'))
        for raw in ('msec=0 request_id=secret status=101', 'msec=nan request_id='+'a'*32+' status=101'):
            self.assertIsNone(c.sanitize('rf_nginx', raw))
        self.assertIsNone(c.sanitize('rf_coturn', {'MESSAGE':'allocation created', '__REALTIME_TIMESTAMP':'bad'}))
        self.assertIsNone(c.sanitize('collaboration','2026-10-04T09:49:00+03:00 stdout F {"event":"connection_closed","channel":"user-secret"}'))

    def test_rotation_restart_cri_partials_and_truncation(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); log=root/'collab.log'; box=c.Outbox(root/'spool')
            start='2026-10-04T09:49:00+03:00 stdout '
            log.write_text(start+'P {"event":"connection_opened",\n')
            reader=c.FileReader(box, {'collaboration':str(log)}); reader.poll()
            self.assertEqual(box.batch(), [])
            with log.open('a') as f: f.write(start+'F "channel":"yjs","token":"CANARY_SECRET"}\n')
            reader.poll(); self.assertEqual(len(box.batch()),1)
            self.assertNotIn('CANARY_SECRET',box.batch()[0][1]); self.assertIn('06:49:00.000Z',box.batch()[0][1])
            log.rename(root/'old.log')
            log.write_text(start+'F {"event":"connection_error","channel":"game"}\n')
            reader.poll(); self.assertEqual(len(box.batch()),2)
            for _, f in reader.handles.values(): f.close()
            reader=c.FileReader(box, {'collaboration':str(log)}); reader.poll()
            self.assertEqual(len(box.batch()),2)
            log.write_text('bad\n'); reader.poll()
            self.assertEqual(len(box.batch()),2)
            for _, f in reader.handles.values(): f.close()
            box.db.close()

    def test_oversize_and_partial_never_become_events(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); log=root/'log'; box=c.Outbox(root/'spool')
            log.write_text('x'*(c.MAX_LINE*2)+'\n'+'2026-10-04T09:49:00Z stdout F {"event":"connection_opened","channel":"yjs"}\n')
            reader=c.FileReader(box, {'collaboration':str(log)}); reader.poll()
            self.assertEqual(len(box.batch()),1)
            for _, f in reader.handles.values(): f.close()

    def test_bounded_outage_recovery_and_dedup_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            box=c.Outbox(directory, 1024*1024)
            record={'source':'livekit','environment':'prod','timestamp':'2026-10-04T06:49:00.000Z','event':'rtc_error'}
            for _ in range(2000): box.enqueue('livekit',record)
            self.assertLess(sum(p.stat().st_size for p in Path(directory).iterdir()),1024*1024)
            self.assertGreater(box.db.execute("SELECT value FROM counters WHERE name='dropped'").fetchone()[0],0)
            before=box.batch()
            with patch.object(c.subprocess,'run') as run:
                run.return_value.returncode=22
                self.assertFalse(box.deliver('/root/no-secrets-in-args.curl')); self.assertEqual(before,box.batch())
                self.assertNotIn('user',str(run.call_args.args[0]))
                run.return_value.returncode=0
                self.assertTrue(box.deliver('/root/no-secrets-in-args.curl'))
            self.assertNotEqual(before,box.batch())
            self.assertEqual(json.loads(before[0][1])['timestamp'],record['timestamp'])

    def test_missing_input_is_not_healthy_silence(self):
        with tempfile.TemporaryDirectory() as directory:
            box=c.Outbox(directory); reader=c.FileReader(box,{'livekit':directory+'/missing-*'})
            reader.poll(); self.assertFalse(reader.available['livekit'])
            c.metrics(box,['livekit'],False,Path(directory)/'metrics',reader.available)
            output=(Path(directory)/'metrics').read_text()
            self.assertIn('honey_prod_logs_input_ok{source="livekit"} 0',output)
            self.assertIn('honey_prod_logs_dropped_total{source="livekit"} 0',output)
            self.assertIn('honey_prod_logs_read_errors_total{source="livekit"} 0',output)

class WindowTest(unittest.TestCase):
    def test_deduplication_and_coverage_do_not_infer_udp(self):
        spec=importlib.util.spec_from_file_location('window',ROOT/'scripts/query-production-log-window.py')
        window=importlib.util.module_from_spec(spec); spec.loader.exec_module(window)
        event={'source':'rf_nginx','event':'signaling_request','event_id':'00000000-0000-4000-8000-000000000001','request_id':'a'*32,'status':101}
        rows=[event,event,dict(event,source='ax41_nginx',event_id='00000000-0000-4000-8000-000000000002'),
              {'source':'livekit','event':'rtc_error','event_id':'00000000-0000-4000-8000-000000000003'},
              {'source':'collaboration','event':'collector_heartbeat','input_ok':'0','event_id':'00000000-0000-4000-8000-000000000004'}]
        report=window.report(rows)
        self.assertEqual(report['paired_signaling_requests'],1)
        self.assertEqual(report['coverage']['rf_nginx']['events'],1)
        self.assertEqual(report['coverage']['collaboration']['state'],'input_unavailable')
        self.assertEqual(report['coverage']['api_route']['state'],'missing_telemetry')
        self.assertIn('does not establish UDP',report['attribution'])
        stored=[dict(row, _msg=row['event']) for row in rows]
        for row in stored: row.pop('event')
        self.assertEqual(window.report(stored),report)

if __name__ == '__main__': unittest.main()
