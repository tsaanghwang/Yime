import copy
import datetime as dt
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from cleanup_actions import cleanup, load_protection, main

OLD = '2026-10-01T00:00:00Z'
NEW = '2026-11-06T00:00:00Z'
SIX_DAYS = '2026-11-01T00:00:00Z'
CUTOFF = dt.datetime(2026, 11, 2, tzinfo=dt.timezone.utc)
RUN_CUTOFF = dt.datetime(2026, 10, 31, tzinfo=dt.timezone.utc)
SHA = 'a' * 40


def artifact(identity, run_id=2, created=OLD, **changes):
    return dict(dict(id=identity, workflow_run={'id': run_id}, name='ordinary',
                     created_at=created, size_in_bytes=10, expired=False), **changes)


def run(identity, **changes):
    return dict(dict(id=identity, created_at=OLD, updated_at=OLD, status='completed',
                     conclusion='success', event='push', head_sha=SHA, run_attempt=1,
                     path='.github/workflows/installed-18u-compile.yml'), **changes)


class API:
    def __init__(self, artifacts=(), runs=(), attached=None):
        self.artifacts = list(artifacts)
        self.runs = list(runs)
        self.attached = attached or {}
        self.deleted = []
        self.refresh = {}
        self.pages = []
        self.calls = []

    def __call__(self, path, method='GET'):
        self.calls.append((path, method))
        if method == 'DELETE':
            self.deleted.append(path)
            identity = int(path.split('/')[-1])
            if '/artifacts/' in path:
                self.artifacts = [a for a in self.artifacts if a['id'] != identity]
                self.attached = {r: [a for a in items if a['id'] != identity]
                                 for r, items in self.attached.items()}
            else:
                self.runs = [r for r in self.runs if r['id'] != identity]
            return True
        url = urlsplit(path)
        if url.query:
            page = int(parse_qs(url.query)['page'][0])
            self.pages.append((url.path, page))
            if url.path == '/actions/artifacts':
                key, data = 'artifacts', self.artifacts
            elif url.path == '/actions/runs':
                key, data = 'workflow_runs', self.runs
            else:
                identity = int(url.path.split('/')[-2])
                key = 'artifacts'
                data = self.attached.get(identity, [a for a in self.artifacts
                                                   if a['workflow_run']['id'] == identity])
            return {key: copy.deepcopy(data[(page-1)*100:page*100]), 'total_count': len(data)}
        if path in self.refresh:
            value = self.refresh[path]
            return copy.deepcopy(value() if callable(value) else value)
        identity = int(path.split('/')[-1])
        source = self.artifacts if '/artifacts/' in path else self.runs
        return copy.deepcopy(next((x for x in source if x['id'] == identity), None))


class CleanupTests(unittest.TestCase):
    def execute(self, api, artifacts=(), runs=(), delete=True, report=None):
        with redirect_stdout(io.StringIO()):
            return cleanup(api, set(artifacts), set(runs), CUTOFF, 999, delete,
                           run_cutoff=RUN_CUTOFF, report=report)

    def test_real_manifest_preserves_original_holds_and_validates_every_record(self):
        path = Path(__file__).with_name('retention-protected.json')
        ids, runs = load_protection(path, 'tsaanghwang/Yime')
        self.assertTrue({13034145597, 13033634731, 13034360087, 13399696130, 13400010403} <= ids)
        self.assertTrue({41178044364, 41993377945} <= runs)
        records = json.loads(path.read_text(encoding='utf-8'))['artifacts']
        self.assertEqual(len(records), len(ids))
        api = API([artifact(a['id'], a['run_id']) for a in records] + [artifact(1)],
                  [run(r) for r in runs] + [run(2)])
        self.execute(api, ids, runs)
        self.assertEqual(api.deleted, ['/actions/artifacts/1', '/actions/runs/2'])

    def test_test12_manifest_keeps_fixed_run_and_digests(self):
        data = json.loads(Path(__file__).with_name('retention-protected.json').read_text(encoding='utf-8'))
        records = {item['id']: item for item in data['artifacts']}
        for identity, digest in (
            (13399696130, 'd1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c'),
            (13400010403, '822ecf6055a96703d182631a5c475f1e81bcfc1d2570540f1ad6a21897202af0'),
        ):
            self.assertEqual(records[identity]['run_id'], 41993377945)
            self.assertEqual(records[identity]['sha256'], digest)

    def test_static_parent_hold_survives_missing_or_expired_artifact(self):
        for present in (False, True):
            with self.subTest(present=present):
                api = API([artifact(1, expired=True)] if present else [], [run(2)])
                self.execute(api, [1], [2])
                self.assertEqual(api.deleted, [])

    def test_parent_protection_does_not_protect_unlisted_sibling(self):
        api = API([artifact(1), artifact(3)], [run(2)])
        self.execute(api, [1], [2])
        self.assertEqual(api.deleted, ['/actions/artifacts/3'])

    def test_protected_artifact_blocks_parent_even_without_explicit_parent_hold(self):
        api = API([artifact(1)], [run(2)])
        self.execute(api, [1])
        self.assertEqual(api.deleted, [])

    def test_five_day_artifacts_and_seven_day_runs_are_separate(self):
        api = API([artifact(1)], [run(2, created_at=SIX_DAYS, updated_at=SIX_DAYS)])
        self.execute(api)
        self.assertEqual(api.deleted, ['/actions/artifacts/1'])

    def test_completed_conclusions_share_policy(self):
        for conclusion in ('success', 'failure', 'cancelled', 'timed_out', 'neutral', None):
            with self.subTest(conclusion=conclusion):
                api = API([artifact(1)], [run(2, conclusion=conclusion)])
                self.execute(api)
                self.assertEqual(api.deleted, ['/actions/artifacts/1', '/actions/runs/2'])

    def test_active_queued_and_current_run_artifacts_and_logs_survive(self):
        for identity, status in ((2, 'in_progress'), (2, 'queued'), (999, 'completed')):
            with self.subTest(identity=identity, status=status):
                api = API([artifact(1, identity)], [run(identity, status=status)])
                self.execute(api)
                self.assertEqual(api.deleted, [])

    def test_recent_rerun_keeps_old_artifacts_and_logs(self):
        api = API([artifact(1)], [run(2, updated_at=NEW)])
        self.execute(api)
        self.assertEqual(api.deleted, [])

    def test_exact_artifact_cutoff_and_recent_upload_block_cascading_run_delete(self):
        for created in (CUTOFF.isoformat(), NEW):
            with self.subTest(created=created):
                api = API([artifact(1, created=created)], [run(2)])
                self.execute(api)
                self.assertEqual(api.deleted, [])

    def test_exact_run_cutoff_is_retained(self):
        for field in ('created_at', 'updated_at'):
            api = API([], [run(2, **{field: RUN_CUTOFF.isoformat()})])
            self.execute(api)
            self.assertEqual(api.deleted, [])

    def test_dry_run_reports_candidates_without_deletion(self):
        report = {}
        api = API([artifact(1, size_in_bytes=123)], [run(2)])
        self.assertEqual(self.execute(api, delete=False, report=report), {'artifacts': 1, 'runs': 1})
        self.assertEqual(api.deleted, [])
        self.assertEqual(report['summary']['candidate_artifact_bytes'], 123)
        self.assertEqual(report['summary']['deleted_artifacts'], 0)
        self.assertEqual(report['summary']['deleted_runs'], 0)
        self.assertEqual(report['candidates']['artifacts'][0]['id'], 1)
        self.assertTrue(report['completed'])

    def test_actual_deletion_count_and_bytes_do_not_double_count_run_cascade(self):
        report = {}
        api = API([artifact(1, size_in_bytes=123)], [run(2)])
        self.execute(api, report=report)
        self.assertEqual(report['summary']['deleted_artifacts'], 1)
        self.assertEqual(report['summary']['deleted_runs'], 1)
        self.assertEqual(report['summary']['deleted_artifact_bytes'], 123)
        self.assertEqual(report['summary']['deleted_run_cascade_bytes'], 0)

    def test_refresh_rechecks_artifact_age_and_disappearance(self):
        for replacement in (None, artifact(1, created=NEW)):
            api = API([artifact(1)], [run(2)])
            api.refresh['/actions/artifacts/1'] = replacement
            self.execute(api, runs=[2])
            self.assertEqual(api.deleted, [])

    def test_refresh_rechecks_parent_rerun_before_artifact_delete(self):
        for replacement in (run(2, status='in_progress'), run(2, updated_at=NEW)):
            api = API([artifact(1)], [run(2)])
            api.refresh['/actions/runs/2'] = replacement
            self.execute(api)
            self.assertEqual(api.deleted, [])

    def test_missing_parent_or_parent_metadata_fails_before_any_deletion(self):
        for missing in (artifact(3, 4), dict(artifact(3), workflow_run={})):
            api = API([artifact(1), missing], [run(2)])
            report = {}
            with self.assertRaises(RuntimeError):
                self.execute(api, report=report)
            self.assertEqual(api.deleted, [])
            self.assertFalse(report['completed'])
            self.assertEqual(len(report['failures']), 1)

    def test_missing_parent_is_fetched_when_not_in_run_listing(self):
        api = API([artifact(1)], [])
        api.refresh['/actions/runs/2'] = run(2)
        self.execute(api)
        self.assertEqual(api.deleted, ['/actions/artifacts/1'])

    def test_all_pages_including_attached_are_checked(self):
        items = [artifact(i) for i in range(1, 101)] + [artifact(101, created=NEW)]
        api = API(items, [run(2)])
        self.execute(api)
        self.assertEqual(len(api.deleted), 100)
        self.assertNotIn('/actions/runs/2', api.deleted)
        self.assertIn(('/actions/artifacts', 2), api.pages)
        self.assertIn(('/actions/runs/2/artifacts', 2), api.pages)

    def test_all_run_pages_are_checked(self):
        api = API([], [run(i) for i in range(1, 102)])
        self.execute(api)
        self.assertEqual(len(api.deleted), 101)
        self.assertIn(('/actions/runs', 2), api.pages)

    def test_failed_global_or_attached_listing_aborts_preflight(self):
        for prefix in ('/actions/runs?', '/actions/runs/2/artifacts?'):
            api = API([artifact(1)], [run(2)])
            def broken(path, method='GET'):
                return None if path.startswith(prefix) else api(path, method)
            with self.assertRaises(RuntimeError):
                self.execute(broken)
            self.assertEqual(api.deleted, [])

    def test_missing_changing_or_incomplete_total_count_fails_closed(self):
        for mode in ('missing', 'incomplete', 'changing', 'duplicate'):
            with self.subTest(mode=mode):
                api = API([artifact(i) for i in range(1, 102)], [run(2)])
                def broken(path, method='GET'):
                    result = api(path, method)
                    if path.startswith('/actions/artifacts?'):
                        if mode == 'missing':
                            result.pop('total_count')
                        if mode == 'incomplete' and 'page=2' in path:
                            result['artifacts'] = []
                        if mode == 'changing' and 'page=2' in path:
                            result['total_count'] = 102
                        if mode == 'duplicate' and 'page=2' in path:
                            result['artifacts'] = [artifact(1)]
                    return result
                with self.assertRaises(RuntimeError):
                    self.execute(broken)
                self.assertEqual(api.deleted, [])

    def test_attachment_absent_from_global_snapshot_blocks_run_delete(self):
        api = API([], [run(2)], {2: [artifact(1)]})
        self.execute(api)
        self.assertEqual(api.deleted, [])

    def test_new_attachment_after_snapshot_blocks_run_delete(self):
        api = API([], [run(2)])
        attached_reads = 0
        def changed(path, method='GET'):
            nonlocal attached_reads
            if path.startswith('/actions/runs/2/artifacts?'):
                attached_reads += 1
                if attached_reads == 2:
                    api.attached[2] = [artifact(1)]
            return api(path, method)
        self.execute(changed)
        self.assertEqual(api.deleted, [])

    def test_run_rerun_after_final_attachment_check_blocks_delete(self):
        api = API([], [run(2)])
        refreshed = iter([run(2), run(2, status='in_progress')])
        api.refresh['/actions/runs/2'] = lambda: next(refreshed)
        self.execute(api)
        self.assertEqual(api.deleted, [])

    def test_delete_404_is_not_reported_as_actual_deletion(self):
        api = API([artifact(1)], [run(2)])
        report = {}
        def vanished(path, method='GET'):
            return False if method == 'DELETE' else api(path, method)
        self.execute(vanished, report=report)
        self.assertEqual(report['summary']['deleted_artifacts'], 0)
        self.assertEqual(report['summary']['deleted_runs'], 0)
        self.assertEqual(sum(s['reason'] == 'already_missing_at_delete' for s in report['skipped']), 2)

    def test_failure_preserves_partial_deletion_report_and_stops(self):
        api = API([artifact(1), artifact(3)], [run(2)])
        report = {}
        def broken(path, method='GET'):
            if path == '/actions/artifacts/3' and method == 'DELETE':
                raise RuntimeError('simulated delete failure')
            return api(path, method)
        with self.assertRaises(RuntimeError):
            self.execute(broken, report=report)
        self.assertEqual(api.deleted, ['/actions/artifacts/1'])
        self.assertFalse(report['completed'])
        self.assertEqual(report['summary']['deleted_artifact_bytes'], 10)
        self.assertEqual(report['failures'][0]['path'], '/actions/artifacts/3')
        self.assertEqual(report['failures'][0]['method'], 'DELETE')

    def test_selected_manual_packages_and_receipts_get_exact_holds_including_old_attempts(self):
        for product, kinds in (('installed-18u', ('x64', 'arm64', 'receipt-x64', 'receipt-arm64')),
                               ('touch-terminal', ('x64', 'arm64', 'receipt'))):
            for kind in kinds:
                for purpose in ('delivery', 'reproduction'):
                    with self.subTest(product=product, kind=kind, purpose=purpose):
                        name = f'selected-{purpose}-{product}-{kind}-{SHA}-attempt-1'
                        path = ('.github/workflows/installed-18u-compile.yml' if product == 'installed-18u'
                                else '.github/workflows/touch-terminal.yml')
                        api = API([artifact(1, name=name), artifact(3)],
                                  [run(2, event='workflow_dispatch', path=path, run_attempt=2)])
                        report = {}
                        self.execute(api, report=report)
                        self.assertEqual(api.deleted, ['/actions/artifacts/3'])
                        self.assertEqual(report['dynamic_selected_holds'][0]['artifact_id'], 1)
                        self.assertEqual(report['protected_run_ids'], [2])

    def test_selected_name_alone_cannot_bypass_event_path_source_or_attempt_validation(self):
        valid = run(2, event='workflow_dispatch')
        for changes in ({'event': 'push'}, {'path': '.github/workflows/another.yml'},
                        {'head_sha': 'b' * 40}, {'run_attempt': 0}, {'run_attempt': None}):
            with self.subTest(changes=changes):
                name = f'selected-delivery-installed-18u-x64-{SHA}-attempt-1'
                api = API([artifact(1, name=name)], [dict(valid, **changes)])
                report = {}
                self.execute(api, report=report)
                self.assertEqual(api.deleted, ['/actions/artifacts/1', '/actions/runs/2'])
                self.assertEqual(report['dynamic_selected_holds'], [])

    def test_similar_selected_prefix_is_ordinary(self):
        api = API([artifact(1, name='selected-delivery-ordinary')], [run(2, event='workflow_dispatch')])
        self.execute(api)
        self.assertEqual(api.deleted, ['/actions/artifacts/1', '/actions/runs/2'])

    def test_manifest_invalid_or_missing_fails_closed(self):
        valid = json.loads(Path(__file__).with_name('retention-protected.json').read_text(encoding='utf-8'))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'policy.json'
            with self.assertRaises(FileNotFoundError):
                load_protection(path, 'tsaanghwang/Yime')
            for field, value in [('id', '*'), ('run_id', 0), ('sha256', 'bad'), ('reason', '')]:
                data = copy.deepcopy(valid)
                data['artifacts'][0][field] = value
                path.write_text(json.dumps(data), encoding='utf-8')
                with self.subTest(field=field), self.assertRaises(ValueError):
                    load_protection(path, 'tsaanghwang/Yime')
            duplicated = copy.deepcopy(valid)
            duplicated['artifacts'].append(duplicated['artifacts'][0])
            path.write_text(json.dumps(duplicated), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_protection(path, 'tsaanghwang/Yime')
            path.write_text(json.dumps(valid), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_protection(path, 'another/repo')

    def test_cli_defaults_to_preview_and_writes_report_on_initialization_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'audit.json'
            with mock.patch('sys.argv', ['cleanup_actions.py', '--report', str(path)]), \
                    mock.patch.dict('os.environ', {}, clear=True), \
                    redirect_stdout(io.StringIO()), self.assertRaises(KeyError):
                main()
            report = json.loads(path.read_text(encoding='utf-8'))
            self.assertFalse(report['delete_enabled'])
            self.assertFalse(report['completed'])
            self.assertEqual(report['failures'][0]['stage'], 'initialization')
            self.assertIn('finished_at_utc', report)


if __name__ == '__main__':
    unittest.main()
