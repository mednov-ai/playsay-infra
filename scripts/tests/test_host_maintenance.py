import importlib.util
from pathlib import Path
import tempfile
import fcntl
import sys
import unittest
from datetime import datetime, timezone
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


m = load('maintenance', 'host-maintenance.py')
nic = load('nic', 'collect-rf-nic-counters.py')


class Maintenance(unittest.TestCase):
    def test_moscow_window_and_clock_uncertainty(self):
        for utc, expected in [('2026-10-23T23:59:59', False), ('2026-10-24T00:00:00', True),
                              ('2026-10-24T01:59:59', True), ('2026-10-24T02:00:00', False),
                              ('2026-10-24T06:32:00', False)]:
            now = datetime.fromisoformat(utc).replace(tzinfo=timezone.utc).timestamp()
            self.assertEqual(m.window(now, True), expected)
            self.assertFalse(m.window(now, False))

    def samples(self):
        return [dict(observed_at=t, counts=dict.fromkeys(m.SOURCES, 0),
                     next_opening_at=2000, authoritative=True) for t in (980, 990)]

    def test_even_two_fresh_zeros_cannot_authorize_restart(self):
        self.assertEqual(m.activity_reason(self.samples(), 1000), 'exclusion_unavailable')

    def test_missing_stale_busy_unknown_malformed_and_lookahead(self):
        self.assertEqual(m.activity_reason(None, 1000), 'activity_missing')
        cases = [({'observed_at': 960}, 'activity_stale'),
                 ({'observed_at': 1001}, 'activity_stale'),
                 ({'counts': {**dict.fromkeys(m.SOURCES, 0), 'dev_turn_allocations': 1}}, 'activity_busy'),
                 ({'counts': {}}, 'activity_unknown'),
                 ({'counts': list(m.SOURCES)}, 'activity_unknown'),
                 ({'counts': dict.fromkeys(m.SOURCES, False)}, 'activity_invalid'),
                 ({'next_opening_at': None}, 'lesson_lookahead'),
                 ({'next_opening_at': 1720}, 'lesson_lookahead'),
                 ({'authoritative': False}, 'activity_unknown')]
        for change, expected in cases:
            samples = self.samples()
            samples[1].update(change)
            self.assertEqual(m.activity_reason(samples, 1000), expected)
        samples = self.samples()
        samples[1]['observed_at'] = 985
        self.assertEqual(m.activity_reason(samples, 1000), 'activity_spacing')

    def test_debt_age_survives_retry_failure_and_install_completion(self):
        initial = m.update({}, 100, (2, 1), 'activity_busy')
        retry = m.update(initial, 100000, (1, 1), 'exclusion_unavailable')
        failed = m.update(retry, 110000, None, 'discovery_failed')
        completed_install = m.update(failed, 120000, (0, 1), 'exclusion_unavailable')
        self.assertEqual(completed_install['restart']['first_pending_at'], 100)
        self.assertEqual(failed['installation']['first_pending_at'], 100)
        self.assertEqual(completed_install['installation'], {'count': 0})

    def test_discovery_cannot_execute_original_upgrade_restart_sequence(self):
        calls = []
        def capture(argv):
            calls.append(argv)
            return 'Inst zlib1g [old] (new)\n' if 'apt-get' in argv[0] else 'NEEDRESTART-SVC: nginx.service\n'
        with patch.object(m, 'capture', capture):
            self.assertEqual(m.discover(), (1, 1))
        self.assertIn('-s', calls[0])
        self.assertEqual(calls[1][-3:], ['-b', '-r', 'l'])
        self.assertFalse(any('systemctl' in word or word in ('install', 'restart') for call in calls for word in call))

    def test_missing_inspector_retains_installation_and_unknown_restart_debt(self):
        def capture(argv):
            if 'needrestart' in argv[0]:
                raise FileNotFoundError()
            return 'Inst zlib1g [old] (new)\n'
        with patch.object(m, 'capture', capture):
            self.assertEqual(m.discover(), (1, None))
        old = m.update({}, 100, (0, 1), 'outside_window')
        current = m.update(old, 200, (1, None), 'discovery_incomplete')
        self.assertFalse(current['discovery_healthy'])
        self.assertEqual(current['restart']['first_pending_at'], 100)
        self.assertEqual(current['installation']['count'], 1)

    def test_overlap_does_not_discover_or_overwrite_debt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'state.json').write_text('{"installation":{"first_pending_at":1}}')
            with (root / 'observer.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with patch.object(sys, 'argv', ['observer', '--owner', 'ax41', '--state-dir', directory]), patch.object(m, 'discover') as discovery:
                    self.assertEqual(m.main(), 0)
                    discovery.assert_not_called()
            self.assertIn('first_pending_at', (root / 'state.json').read_text())
            self.assertFalse((root / 'metrics.prom').exists())

    def test_atomic_persistence_and_safe_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'state.json'
            m.atomic(path, '{}')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        state = m.update({}, 100, (1, 1), 'activity_missing')
        self.assertIn('disruptive_capability{owner="ax41"} 0', m.metrics(state, 'ax41'))


class Nic(unittest.TestCase):
    def fixture(self, root, interface, values):
        directory = Path(root) / interface / 'statistics'
        directory.mkdir(parents=True, exist_ok=True)
        for field, value in values.items():
            (directory / field).write_text(str(value))

    def test_exact_named_sum_excludes_packets_bytes_and_other_interfaces(self):
        with tempfile.TemporaryDirectory() as root:
            self.fixture(root, 'eth0', dict(rx_errors=1, rx_dropped=5, tx_errors=2, tx_dropped=3,
                                          rx_packets=691355, tx_packets=999999, rx_bytes=123456789))
            self.fixture(root, 'lo', dict.fromkeys(nic.FIELDS, 100))
            self.fixture(root, 'tun0', dict.fromkeys(nic.FIELDS, 100))
            output, ok = nic.collect(root, ['eth0'], 1000)
            self.assertTrue(ok)
            self.assertIn('nic_error_drop_total{semantics_version="2"} 11\n', output)
            self.fixture(root, 'eth0', {'rx_packets': 99999999999, 'tx_packets': 99999999999})
            self.assertEqual(nic.collect(root, ['eth0'], 1000)[0], output)
            self.fixture(root, 'eth0', dict.fromkeys(nic.FIELDS, 0))
            self.assertIn('nic_error_drop_total{semantics_version="2"} 0\n', nic.collect(root, ['eth0'], 1010)[0])

    def test_failure_emits_health_only_no_fabricated_counter_or_fresh_healthy_time(self):
        with tempfile.TemporaryDirectory() as root:
            for value in ('bad', '-1', '1.5', ''):
                self.fixture(root, 'eth0', dict.fromkeys(nic.FIELDS, value))
                output, ok = nic.collect(root, ['eth0'], 1000)
                self.assertFalse(ok)
                self.assertEqual(output, 'playsay_rf_host_nic_collection_healthy{semantics_version="2"} 0\n')
            (Path(root) / 'eth0/statistics/rx_errors').unlink()
            self.assertFalse(nic.collect(root, ['eth0'], 1000)[1])
            for interfaces in ([], ['lo'], ['../eth0'], ['eth0', 'eth0']):
                with self.assertRaises(ValueError):
                    nic.collect(root, interfaces, 1000)


if __name__ == '__main__':
    unittest.main()
