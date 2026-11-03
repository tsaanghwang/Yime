import copy
import datetime as dt
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

from cleanup_actions import cleanup, load_protection

OLD = '2026-10-01T00:00:00Z'
NEW = '2026-11-02T00:00:00Z'
CUTOFF = dt.datetime(2026, 10, 26, tzinfo=dt.timezone.utc)


def artifact(id, created=OLD):
    return dict(id=id, created_at=created, expires_at='2026-11-14T00:00:00Z')


def run(id, **changes):
    return dict(dict(id=id, created_at=OLD, updated_at=OLD, status='completed'), **changes)


class API:
    def __init__(self, artifacts=(), runs=(), attached=None):
        self.artifacts = list(artifacts)
        self.runs = list(runs)
        self.attached = attached or {}
        self.deleted = []
        self.refresh = {}
        self.pages = []

    def __call__(self, path, method='GET'):
        if method == 'DELETE':
            self.deleted.append(path)
            return None
        url = urlsplit(path)
        if url.query:
            page = int(parse_qs(url.query)['page'][0])
            self.pages.append((url.path, page))
            if url.path == '/actions/artifacts':
                key, data = 'artifacts', self.artifacts
            elif url.path == '/actions/runs':
                key, data = 'workflow_runs', self.runs
            else:
                key, data = 'artifacts', self.attached.get(int(url.path.split('/')[-2]), [])
            return {key: data[(page-1)*100:page*100]}
        if path in self.refresh:
            return self.refresh[path]
        id = int(path.split('/')[-1])
        return next(x for x in self.artifacts + self.runs if x['id'] == id)


class CleanupTests(unittest.TestCase):
    def execute(self, api, artifacts=(), runs=(), delete=True):
        with redirect_stdout(io.StringIO()):
            return cleanup(api, set(artifacts), set(runs), CUTOFF, 999, delete)

    def test_real_manifest_protects_packages_report_and_parent(self):
        ids, runs = load_protection(Path(__file__).with_name('retention-protected.json'), 'tsaanghwang/Yime')
        self.assertEqual(ids, {13034145597, 13033634731, 13034360087})
        self.assertEqual(runs, {41178044364})
        api = API([artifact(i) for i in ids] + [artifact(1)], [run(41178044364), run(2)])
        self.execute(api, ids, runs)
        self.assertEqual(api.deleted, ['/actions/artifacts/1', '/actions/runs/2'])

    def test_parent_hold_survives_missing_or_expired_artifacts(self):
        api = API([], [run(41178044364)])
        self.execute(api, [13034145597], [41178044364])
        self.assertEqual(api.deleted, [])

    def test_attached_protected_artifact_blocks_unlisted_parent(self):
        api = API([], [run(2)], {2: [artifact(1)]})
        self.execute(api, [1])
        self.assertEqual(api.deleted, [])

    def test_dry_run_never_deletes_artifacts_or_runs(self):
        api = API([artifact(1)], [run(2)])
        self.assertEqual(self.execute(api, delete=False), {'artifacts': 1, 'runs': 1})
        self.assertEqual(api.deleted, [])

    def test_recent_active_updated_and_current_runs_survive(self):
        api = API([artifact(1, NEW)], [run(2, status='in_progress'), run(3, updated_at=NEW), run(999), run(4)], {4: [artifact(1, NEW)]})
        self.execute(api)
        self.assertEqual(api.deleted, [])

    def test_exact_cutoff_is_not_old(self):
        api = API([artifact(1, CUTOFF.isoformat())], [run(2, created_at=CUTOFF.isoformat())])
        self.execute(api)
        self.assertEqual(api.deleted, [])

    def test_refresh_rechecks_changed_and_disappeared_objects(self):
        api = API([artifact(1), artifact(2)], [run(3)])
        api.refresh = {'/actions/artifacts/1': artifact(1, NEW), '/actions/artifacts/2': None, '/actions/runs/3': run(3, status='in_progress')}
        self.execute(api)
        self.assertEqual(api.deleted, [])

    def test_all_pages_including_attached_are_checked(self):
        api = API([artifact(i) for i in range(1, 102)], [run(500)], {500: [artifact(i) for i in range(200, 300)] + [artifact(400, NEW)]})
        self.execute(api, [101])
        self.assertEqual(len(api.deleted), 100)
        self.assertNotIn('/actions/artifacts/101', api.deleted)
        self.assertNotIn('/actions/runs/500', api.deleted)
        self.assertIn(('/actions/artifacts', 2), api.pages)
        self.assertIn(('/actions/runs/500/artifacts', 2), api.pages)

    def test_listing_failure_aborts_before_deletion(self):
        api = API([artifact(1)], [run(2)])
        def broken(path, method='GET'):
            return None if path.startswith('/actions/runs?') else api(path, method)
        with self.assertRaises(RuntimeError):
            self.execute(broken)
        self.assertEqual(api.deleted, [])

    def test_manifest_invalid_or_missing_fails_closed(self):
        valid = json.loads(Path(__file__).with_name('retention-protected.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'policy.json'
            with self.assertRaises(FileNotFoundError):
                load_protection(path, 'tsaanghwang/Yime')
            for field, value in [('id', '*'), ('run_id', 0), ('sha256', 'bad'), ('reason', '')]:
                data = copy.deepcopy(valid)
                data['artifacts'][0][field] = value
                path.write_text(json.dumps(data))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    load_protection(path, 'tsaanghwang/Yime')
            path.write_text(json.dumps(valid))
            with self.assertRaises(ValueError):
                load_protection(path, 'another/repo')


if __name__ == '__main__':
    unittest.main()
