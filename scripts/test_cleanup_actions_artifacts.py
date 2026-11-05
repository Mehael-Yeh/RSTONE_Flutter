"""Synthetic fixtures only; no credentials and no real deletions."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('cleanup', Path(__file__).with_name('cleanup_actions_artifacts.py'))


cleanup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cleanup)
from datetime import datetime, timezone
import copy

NOW = datetime(2030, 1, 10, tzinfo=timezone.utc)
REPO = 'Mehael-Yeh/RSTONE_Flutter'
SHA = 'a' * 40


def run(i, path='release_alpha.yml', status='completed', conclusion='success', branch='main'):
    return dict(id=i, path='.github/workflows/' + path, status=status,
                conclusion=conclusion if status == 'completed' else None,
                head_sha=SHA, head_branch=branch, run_number=i, run_attempt=1,
                repository=dict(id=10, full_name=REPO), head_repository=dict(id=10, full_name=REPO),
                created_at='2030-01-01T00:00:00Z', updated_at='2030-01-02T00:00:00Z')


def artifact(i, name='RSTONE-v1.2.3-alpha', rid=None):
    return dict(id=i, name=name, size_in_bytes=123, expired=False,
                created_at='2030-01-03T00:00:00Z',
                workflow_run=dict(id=i if rid is None else rid, repository_id=10,
                                  head_repository_id=10, head_sha=SHA, head_branch='main'))


def snapshot(artifacts, runs):
    return dict(repository=dict(id=10, full_name=REPO, default_branch='main', private=False),
                artifacts=artifacts, runs=runs)


class PolicyTests(unittest.TestCase):
    def plan(self, artifacts, runs, **kw):
        return cleanup.plan(snapshot(artifacts, runs), NOW, **kw)

    def test_only_old_redundant_alpha(self):
        self.assertEqual([1], [a['id'] for a in self.plan([artifact(1), artifact(2)], [run(1), run(2)])])

    def test_unknown_stable_and_evidence_preserved(self):
        for name in ['RSTONE-v1.2.3', 'apk-independent-acceptance', 'data-publication-report',
                     'RSTONE-v1.2.3-alpha-extra', 'RSTONE-v1.2-alpha', 'other']:
            self.assertEqual([], self.plan([artifact(1, name), artifact(2)], [run(1), run(2)]))

    def test_active_newest_and_wrong_workflow_are_preserved(self):
        for r in [run(1, status='in_progress'), run(1, path='other.yml')]:
            self.assertEqual([], self.plan([artifact(1), artifact(2)], [r, run(2)]))

    def test_recent_expired_future_and_bad_integer(self):
        for key, value in [('created_at', '2030-01-09T00:00:00Z'), ('expired', True)]:
            a = artifact(1); a[key] = value
            newer = artifact(2); newer['created_at'] = '2030-01-09T12:00:00Z'
            self.assertEqual([], self.plan([a, newer], [run(1), run(2)]))
        for key, value in [('created_at', '2030-01-11T00:00:00Z'), ('id', True), ('size_in_bytes', True)]:
            a = artifact(1); a[key] = value
            with self.assertRaises(cleanup.Unsafe): self.plan([a], [run(1)])

    def test_timezone_boundary(self):
        a = artifact(1); a['created_at'] = '2030-01-08T08:00:00+08:00'
        newer = artifact(2); newer['created_at'] = '2030-01-09T00:00:00Z'
        self.assertEqual([1], [x['id'] for x in self.plan([a, newer], [run(1), run(2)])])
        a['created_at'] = '2030-01-08T00:00:01Z'
        self.assertEqual([], self.plan([a, newer], [run(1), run(2)]))
        a['created_at'] = '2030-01-01T00:00:00'
        with self.assertRaises(cleanup.Unsafe): self.plan([a], [run(1)])

    def test_pages_latest_success_not_failed_newest(self):
        runs = [run(1, 'deploy_web_pages.yml'), run(2, 'deploy_web_pages.yml'),
                run(3, 'deploy_web_pages.yml', conclusion='failure')]
        runs[1]['updated_at'] = '2030-01-04T00:00:00Z'
        self.assertEqual([1], [x['id'] for x in self.plan([artifact(i, 'github-pages') for i in (1,2,3)], runs)])
        runs[2]['status'] = 'in_progress'; runs[2]['conclusion'] = None
        self.assertEqual([], self.plan([artifact(i, 'github-pages') for i in (1,2,3)], runs))

    def test_pages_wrong_branch_workflow_or_sha_preserved(self):
        for field, value in [('head_branch','feature'), ('path','.github/workflows/other.yml')]:
            r = run(1, 'deploy_web_pages.yml'); r[field] = value
            a = artifact(1, 'github-pages'); a['workflow_run']['head_branch'] = r['head_branch']
            newer_run = run(2, 'deploy_web_pages.yml'); newer_run['updated_at'] = '2030-01-04T00:00:00Z'
            self.assertEqual([], self.plan([a, artifact(2, 'github-pages')], [r, newer_run]))
        a = artifact(1); a['workflow_run']['head_sha'] = 'b' * 40
        with self.assertRaises(cleanup.Unsafe): self.plan([a], [run(1)])

    def test_duplicate_missing_metadata_unknown_repo_and_cap_abort(self):
        for s in [snapshot([artifact(1), artifact(1)], [run(1)]),
                  snapshot([artifact(1)], []), snapshot([artifact(1)], [dict(id=1)])]:
            with self.assertRaises(cleanup.Unsafe): cleanup.plan(s, NOW)
        s = snapshot([], []); s['repository']['full_name'] = 'other/repo'
        with self.assertRaises(cleanup.Unsafe): cleanup.plan(s, NOW)
        with self.assertRaises(cleanup.Unsafe):
            self.plan([artifact(i) for i in range(1,23)], [run(i) for i in range(1,23)])

    def test_pages_active_without_artifact_and_recent_rerun(self):
        runs = [run(i, 'deploy_web_pages.yml') for i in (1,2,3)]
        runs[1]['updated_at'] = '2030-01-05T00:00:00Z'
        runs[2]['updated_at'] = '2030-01-06T00:00:00Z'
        artifacts = [artifact(i, 'github-pages') for i in (1,2,3)]
        self.assertEqual([1,2], [a['id'] for a in self.plan(artifacts, runs)])
        runs.append(run(4, 'deploy_web_pages.yml', status='queued'))
        self.assertEqual([], self.plan(artifacts, runs))
        runs.pop()
        runs[0]['updated_at'] = '2030-01-07T00:00:00Z'
        # Old source rerun deployed most recently, and highest source sequence retained too.
        self.assertEqual([2], [a['id'] for a in self.plan(artifacts, runs)])

    def test_exact_delete_limit_and_newest_completed_alpha(self):
        self.assertEqual(20, len(self.plan([artifact(i) for i in range(1,22)],
                                         [run(i) for i in range(1,22)])))
        runs = [run(1), run(2), run(3, status='in_progress')]
        self.assertEqual([1], [a['id'] for a in self.plan([artifact(i) for i in (1,2,3)], runs)])

    def test_api_redirect_get_retry_and_delete_no_retry(self):
        import io
        import urllib.error
        from unittest.mock import patch
        class Response(io.BytesIO):
            def __init__(self, status=200):
                super().__init__(b'{"safe":true}'); self.status = status
        class Opener:
            def __init__(self, failure=None, status=200):
                self.calls, self.failure, self.status = 0, failure, status
            def open(self, req, timeout):
                self.calls += 1
                if self.failure: raise self.failure
                return Response(self.status)
        with self.assertRaises(cleanup.Unsafe):
            cleanup.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://evil.example')
        api = cleanup.API('synthetic-not-a-real-token')
        with patch.object(cleanup.time, 'sleep'):
            api.opener = Opener(urllib.error.URLError('synthetic'))
            with self.assertRaises(cleanup.Unsafe): api.request(BASE_PATH)
            self.assertEqual(3, api.opener.calls)
            api.opener = Opener(urllib.error.URLError('synthetic'))
            with self.assertRaises(cleanup.Unsafe): api.request(BASE_PATH + '/actions/artifacts/1', 'DELETE')
            self.assertEqual(1, api.opener.calls)
            api.opener = Opener(status=200)
            with self.assertRaises(cleanup.Unsafe): api.request(BASE_PATH + '/actions/artifacts/1', 'DELETE')
            self.assertEqual(1, api.opener.calls)
            api.opener = Opener(status=204)
            self.assertIsNone(api.request(BASE_PATH + '/actions/artifacts/1', 'DELETE'))
            api.opener = Opener(urllib.error.HTTPError('https://api.github.com', 404, '', {}, None))
            self.assertIsNone(api.request(BASE_PATH + '/actions/artifacts/1', missing=True))
            self.assertEqual(1, api.opener.calls)

    def test_boolean_repository_identity_is_rejected(self):
        s = snapshot([], []); s['repository']['id'] = True
        with self.assertRaises(cleanup.Unsafe): cleanup.plan(s, NOW)
        s = snapshot([artifact(1), artifact(2)], [run(1), run(2)])
        s['runs'][0]['head_repository']['id'] = True
        s['artifacts'][0]['workflow_run']['head_repository_id'] = True
        with self.assertRaises(cleanup.Unsafe): cleanup.plan(s, NOW)

    def test_implementation_exists(self):
        self.assertTrue(Path(SPEC.origin).is_file(), 'safe cleanup implementation is missing')


class TransportTests(unittest.TestCase):
    def setUp(self):
        # Keep synthetic apply output out of real execution receipts.
        import contextlib
        import io
        context = contextlib.redirect_stdout(io.StringIO())
        context.__enter__()
        self.addCleanup(context.__exit__, None, None, None)

    def test_cli_default_is_read_only(self):
        from unittest.mock import patch
        import contextlib
        import io
        api = SyntheticAPI()
        # Isolate clock/network; assert the parsed default argument passed to the engine.
        with patch.object(cleanup, 'API', return_value=api), patch.dict(cleanup.os.environ, {}, clear=True):
            with patch.object(cleanup, 'execute', return_value={'mode': 'dry-run'}) as engine:
                self.assertEqual(0, cleanup.main([]))
                engine.assert_called_once_with(api, False)
            self.assertEqual(0, api.deletes)
        with patch.dict(cleanup.os.environ, {}, clear=True), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(1, cleanup.main([]))

    def test_safe_url_boundary(self):
        for path in ['https://evil.example/x', BASE_PATH + '/actions/artifacts/1/zip',
                     BASE_PATH + '/actions/caches', BASE_PATH + '/../other',
                     '/repos/other/repo/actions/artifacts', BASE_PATH + '/actions/artifacts?per_page=100&page=0']:
            with self.assertRaises(cleanup.Unsafe): cleanup.safe_url(path, 'GET')
        with self.assertRaises(cleanup.Unsafe): cleanup.safe_url(BASE_PATH + '/actions/runs/1', 'DELETE')
        self.assertEqual('https://api.github.com' + BASE_PATH, cleanup.safe_url(BASE_PATH, 'GET'))

    def test_pagination_full_to_empty_and_total_consistency(self):
        calls = []
        def request(path, method='GET', missing=False):
            calls.append(path)
            n = len(calls)
            return dict(total_count=2, artifacts=[dict(id=n)] if n < 3 else [])
        self.assertEqual([1,2], [x['id'] for x in cleanup.collection(request, '/actions/artifacts', 'artifacts', 5000)])
        self.assertEqual(3, len(calls))
        def bad(path, **kw): return dict(total_count=2, artifacts=[])
        with self.assertRaises(cleanup.Unsafe): cleanup.collection(bad, '/actions/artifacts', 'artifacts', 5000)
        def dup(path, **kw): return dict(total_count=2, artifacts=[dict(id=1)])
        with self.assertRaises(cleanup.Unsafe): cleanup.collection(dup, '/actions/artifacts', 'artifacts', 5000)
        def capped(path, **kw): return dict(total_count=1000, workflow_runs=[])
        with self.assertRaises(cleanup.Unsafe): cleanup.collection(capped, '/actions/runs', 'workflow_runs', 999)
        def boolean(path, **kw): return dict(total_count=True, artifacts=[])
        with self.assertRaises(cleanup.Unsafe): cleanup.collection(boolean, '/actions/artifacts', 'artifacts', 5000)

    def test_delete_single_attempt_and_readback_verification(self):
        for fail in ('delete', 'get', 'listing', None):
            api = SyntheticAPI(fail=fail)
            if fail:
                with self.assertRaises(cleanup.Unsafe): cleanup.execute(api, True, clock=lambda: NOW)
            else:
                result = cleanup.execute(api, True, clock=lambda: NOW)
                self.assertEqual([1], result['deleted_ids'])
            self.assertEqual(1, api.deletes)

    def test_dry_run_never_deletes_and_race_stops(self):
        api = SyntheticAPI()
        self.assertEqual('dry-run', cleanup.execute(api, False, clock=lambda: NOW)['mode'])
        self.assertEqual(0, api.deletes)
        api = SyntheticAPI(race=True)
        with self.assertRaises(cleanup.Unsafe): cleanup.execute(api, True, clock=lambda: NOW)
        self.assertEqual(0, api.deletes)


BASE_PATH = '/repos/' + REPO


class SyntheticAPI:
    """In-memory fake only; never connects to GitHub."""
    def __init__(self, fail=None, race=False):
        self.fail, self.race, self.deletes, self.snapshots = fail, race, 0, 0
        self.state = snapshot([artifact(1), artifact(2)], [run(1), run(2)])

    def snapshot(self):
        self.snapshots += 1
        state = copy.deepcopy(self.state)
        if self.race and self.snapshots > 1:
            state['runs'][0]['status'] = 'in_progress'
            state['runs'][0]['conclusion'] = None
        return state

    def request(self, path, method='GET', missing=False):
        if method == 'DELETE':
            self.deletes += 1
            if self.fail == 'delete': raise cleanup.Unsafe('synthetic ambiguous DELETE')
            if self.fail != 'listing': self.state['artifacts'].pop(0)
            return None
        if '/actions/artifacts/' in path:
            if self.deletes:
                if self.fail == 'get': return artifact(1)
                return None
            return artifact(1)
        if '/actions/runs/' in path: return run(1)
        raise AssertionError('unexpected synthetic route')


if __name__ == '__main__':
    unittest.main()
