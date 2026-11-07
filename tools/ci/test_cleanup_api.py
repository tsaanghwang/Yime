import datetime as dt
from email.utils import format_datetime
import io
import json
from contextlib import redirect_stdout
import unittest
from urllib.error import HTTPError
from urllib.parse import urlsplit

from cleanup_actions import GitHubAPI, RecheckRequired, cleanup
from test_cleanup_actions import API, CUTOFF, RUN_CUTOFF, NEW, artifact, run


class FakeTime:
    def __init__(self):
        self.elapsed = 0
        self.sleeps = []

    def monotonic(self):
        return self.elapsed

    def clock(self):
        return 1000 + self.elapsed

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.elapsed += seconds


def error(status=429, headers=None, message='rate limit exceeded'):
    return HTTPError('https://example.invalid/actions', status, 'simulated', headers or {},
                     io.BytesIO(json.dumps({'message': message}).encode()))


def response(value):
    return io.BytesIO(json.dumps(value).encode())


class CleanupAPITests(unittest.TestCase):
    def client(self, outcomes, **kwargs):
        report, clock, calls = {}, FakeTime(), []
        pending = iter(outcomes)
        def opener(request, timeout):
            calls.append((request.get_method(), request.full_url, clock.elapsed))
            outcome = next(pending)
            if isinstance(outcome, BaseException):
                raise outcome
            return response(outcome)
        api = GitHubAPI('https://example.invalid', {}, report, opener=opener,
                        sleep=clock.sleep, monotonic=clock.monotonic, clock=clock.clock, **kwargs)
        return api, clock, calls, report

    def test_primary_reset_waits_in_at_most_sixty_second_chunks(self):
        api, clock, calls, report = self.client([
            error(403, {'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '1125'}), {'id': 1}])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(api('/actions/artifacts/1'), {'id': 1})
        self.assertEqual(clock.sleeps, [60, 60, 6])
        self.assertEqual(len(calls), 2)
        self.assertEqual(report['api']['rate_limit_wait_seconds'], 126)

    def test_retry_after_and_primary_reset_both_respected(self):
        api, clock, _, _ = self.client([
            error(429, {'Retry-After': '10', 'X-RateLimit-Remaining': '0',
                        'X-RateLimit-Reset': '1020'}), {}])
        with redirect_stdout(io.StringIO()):
            api('/actions/runs')
        self.assertEqual(clock.elapsed, 21)

    def test_http_date_retry_after_is_supported(self):
        date = format_datetime(dt.datetime.fromtimestamp(1010, dt.timezone.utc), usegmt=True)
        api, clock, _, _ = self.client([error(429, {'Retry-After': date}), {}])
        with redirect_stdout(io.StringIO()):
            api('/actions/runs')
        self.assertEqual(clock.elapsed, 10)

    def test_secondary_error_without_headers_uses_exponential_backoff(self):
        api, clock, calls, _ = self.client([error(403), error(403), {}])
        with redirect_stdout(io.StringIO()):
            api('/actions/runs')
        self.assertEqual(clock.sleeps, [60, 60, 60])
        self.assertEqual(len(calls), 3)

    def test_plain_forbidden_and_server_errors_are_not_retried(self):
        for status in (403, 500):
            with self.subTest(status=status):
                failure = error(status, {'X-RateLimit-Remaining': '10'}, 'Resource not accessible')
                api, clock, calls, _ = self.client([failure])
                with self.assertRaises(HTTPError) as raised:
                    api('/actions/runs')
                self.assertIs(raised.exception, failure)
                self.assertEqual(clock.sleeps, [])
                self.assertEqual(len(calls), 1)

    def test_retry_count_and_overall_deadline_are_bounded(self):
        api, clock, calls, _ = self.client(
            [error(429, {'Retry-After': '1'}) for _ in range(3)], max_retries=2)
        with redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, 'retry limit'):
            api('/actions/runs')
        self.assertEqual(clock.sleeps, [1, 1])
        self.assertEqual(len(calls), 3)
        api, clock, calls, _ = self.client([error(429, {'Retry-After': '20'})], deadline_seconds=10)
        with self.assertRaises(TimeoutError):
            api('/actions/runs')
        self.assertEqual(clock.sleeps, [])
        self.assertEqual(len(calls), 1)

    def test_rate_limited_delete_returns_to_caller_without_resending(self):
        api, clock, calls, report = self.client([error(429, {'Retry-After': '2'}), True])
        with redirect_stdout(io.StringIO()), self.assertRaises(RecheckRequired):
            api('/actions/artifacts/1', 'DELETE')
        self.assertEqual(len(calls), 1)
        self.assertEqual(clock.elapsed, 2)
        self.assertTrue(api('/actions/artifacts/1', 'DELETE'))
        self.assertEqual(len(calls), 2)
        self.assertEqual(report['api']['rate_limit_retries'], 1)

    def test_delete_rate_retry_count_survives_intervening_get_checks(self):
        api, _, _, _ = self.client([error(429, {'Retry-After': '2'}), {},
                                    error(429, {'Retry-After': '2'})], max_retries=1)
        with redirect_stdout(io.StringIO()), self.assertRaises(RecheckRequired):
            api('/actions/artifacts/1', 'DELETE')
        api('/actions/artifacts/1')
        with self.assertRaisesRegex(RuntimeError, 'retry limit'):
            api('/actions/artifacts/1', 'DELETE')

    def test_delete_pacing_happens_before_get_rechecks(self):
        api, clock, calls, _ = self.client([True, {}, True])
        api('/actions/artifacts/1', 'DELETE')
        self.assertTrue(api.prepare_delete())
        api('/actions/artifacts/2')
        api('/actions/artifacts/2', 'DELETE')
        self.assertEqual(clock.sleeps, [1])
        self.assertEqual([entry[2] for entry in calls], [0, 1, 1])

    def test_missing_get_and_delete_keep_existing_semantics(self):
        api, _, _, _ = self.client([error(404), error(404)])
        self.assertIsNone(api('/actions/artifacts/1'))
        self.assertIs(api('/actions/artifacts/1', 'DELETE'), False)

    def integration_client(self, data, intercept, **kwargs):
        report, clock = {}, FakeTime()
        def opener(request, timeout):
            url = urlsplit(request.full_url)
            path = url.path + ('?' + url.query if url.query else '')
            intercept(path, request.get_method(), clock)
            return response(data(path, request.get_method()))
        api = GitHubAPI('https://example.invalid', {}, report, opener=opener,
                        sleep=clock.sleep, monotonic=clock.monotonic, clock=clock.clock, **kwargs)
        return api, clock, report

    def execute(self, api, report):
        with redirect_stdout(io.StringIO()):
            cleanup(api, set(), set(), CUTOFF, 999, True, run_cutoff=RUN_CUTOFF, report=report)

    def test_artifact_delete_rechecks_parent_after_wait_and_keeps_started_rerun(self):
        data = API([artifact(1)], [run(2)])
        def intercept(path, method, clock):
            if method == 'DELETE':
                data.refresh['/actions/runs/2'] = run(2, status='in_progress', updated_at=NEW)
                raise error(429, {'Retry-After': '2'})
        api, _, report = self.integration_client(data, intercept)
        self.execute(api, report)
        self.assertEqual(data.deleted, [])
        self.assertEqual(report['summary']['deleted_artifacts'], 0)
        self.assertEqual(report['api']['rate_limit_retries'], 1)
        self.assertTrue(any(s['reason'] == 'parent_not_completed' for s in report['skipped']))

    def test_run_delete_rechecks_attachments_after_wait(self):
        data = API([], [run(2)])
        def intercept(path, method, clock):
            if method == 'DELETE':
                data.attached[2] = [artifact(1, created=NEW)]
                raise error(429, {'Retry-After': '2'})
        api, _, report = self.integration_client(data, intercept)
        self.execute(api, report)
        self.assertEqual(data.deleted, [])
        self.assertEqual(report['api']['rate_limit_retries'], 1)
        self.assertTrue(any(s['reason'] == 'attachment_set_changed' for s in report['skipped']))

    def test_successful_retry_records_candidate_once_and_deletes_once(self):
        data = API([artifact(1)], [run(2)])
        limited = False
        def intercept(path, method, clock):
            nonlocal limited
            if method == 'DELETE' and not limited:
                limited = True
                raise error(429, {'Retry-After': '2'})
        api, _, report = self.integration_client(data, intercept)
        self.execute(api, report)
        self.assertEqual(data.deleted, ['/actions/artifacts/1', '/actions/runs/2'])
        self.assertEqual(report['summary']['candidate_artifacts'], 1)
        self.assertEqual(report['summary']['deleted_artifacts'], 1)
        self.assertEqual(report['summary']['deleted_artifact_bytes'], 10)

    def test_final_run_get_rechecks_status_after_rate_limit_wait(self):
        data = API([], [run(2)])
        reads = 0
        def intercept(path, method, clock):
            nonlocal reads
            if path == '/actions/runs/2' and method == 'GET':
                reads += 1
                if reads == 2:
                    data.refresh[path] = run(2, status='in_progress', updated_at=NEW)
                    raise error(429, {'Retry-After': '2'})
        api, _, report = self.integration_client(data, intercept)
        self.execute(api, report)
        self.assertEqual(data.deleted, [])
        self.assertEqual(reads, 3)
        self.assertEqual(report['api']['rate_limit_retries'], 1)

    def test_plain_forbidden_preserves_partial_report_without_rate_retry(self):
        data = API([artifact(1), artifact(3)], [run(2)])
        def intercept(path, method, clock):
            if path == '/actions/artifacts/3' and method == 'DELETE':
                raise error(403, message='Resource not accessible')
        api, clock, report = self.integration_client(data, intercept)
        with self.assertRaises(HTTPError):
            self.execute(api, report)
        self.assertEqual(data.deleted, ['/actions/artifacts/1'])
        self.assertEqual(clock.sleeps, [1])
        self.assertFalse(report['completed'])
        self.assertEqual(report['api']['rate_limit_retries'], 0)
        self.assertEqual(report['summary']['deleted_artifacts'], 1)
        self.assertEqual(report['failures'][0]['type'], 'HTTPError')

    def test_deadline_failure_keeps_actual_partial_deletions_in_report(self):
        data = API([artifact(1), artifact(3)], [run(2)])
        def intercept(path, method, clock):
            if path == '/actions/artifacts/3' and method == 'DELETE':
                raise error(403, {'Retry-After': '20'})
        api, _, report = self.integration_client(data, intercept, deadline_seconds=10)
        with self.assertRaises(TimeoutError):
            self.execute(api, report)
        self.assertEqual(data.deleted, ['/actions/artifacts/1'])
        self.assertFalse(report['completed'])
        self.assertEqual(report['summary']['deleted_artifacts'], 1)
        self.assertEqual(report['summary']['deleted_artifact_bytes'], 10)
        self.assertEqual(report['failures'][0]['type'], 'TimeoutError')
        self.assertEqual(report['failures'][0]['path'], '/actions/artifacts/3')


if __name__ == '__main__':
    unittest.main()
