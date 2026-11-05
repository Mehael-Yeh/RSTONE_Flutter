"""Conservative, repository-local Actions artifact retention (stdlib only).

No cache, run, log or Release endpoints. Unrecognized artifacts are retained.
All fixtures in the companion tests are synthetic, not deletion receipts.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

REPOSITORY = 'Mehael-Yeh/RSTONE_Flutter'
BASE = '/repos/' + REPOSITORY
ALPHA = '.github/workflows/release_alpha.yml'
PAGES = '.github/workflows/deploy_web_pages.yml'
ALPHA_NAME = re.compile(r'RSTONE-v[0-9]+\.[0-9]+\.[0-9]+-alpha', re.ASCII)
SHA = re.compile(r'[0-9a-f]{40}', re.ASCII)
MAX_DELETE = 20


class Unsafe(Exception):
    """Incomplete or changed evidence: stop without expanding scope."""


def require(condition, message):
    if not condition:
        raise Unsafe(message)


def integer(value, minimum=1):
    require(type(value) is int and value >= minimum, 'invalid integer metadata')
    return value


def timestamp(value, now):
    require(isinstance(value, str), 'missing timestamp')
    try:
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        raise Unsafe('invalid timestamp') from None
    require(result.tzinfo is not None and result.utcoffset() is not None, 'naive timestamp')
    result = result.astimezone(timezone.utc)
    require(result <= now, 'future timestamp')
    return result


def unique(rows):
    require(isinstance(rows, list), 'missing collection')
    ids = [integer(r.get('id')) for r in rows]
    require(len(ids) == len(set(ids)), 'duplicate IDs')
    return {r['id']: r for r in rows}


def plan(state, now):
    require(now.tzinfo is not None and now.utcoffset() is not None, 'naive clock')
    repo = state['repository']
    require(repo.get('full_name') == REPOSITORY and repo.get('private') is False,
            'repository not allowlisted public repository')
    repo_id = integer(repo.get('id'))
    branch = repo.get('default_branch')
    require(isinstance(branch, str) and branch, 'missing default branch')
    runs = unique(state['runs'])
    artifacts = unique(state['artifacts'])
    require(len(runs) < 1000 and len(artifacts) <= 5000, 'collection safety ceiling')
    for r in runs.values():
        for key in ('repository', 'head_repository'):
            require(isinstance(r.get(key), dict), 'missing run repository')
            integer(r[key].get('id'))
            require(isinstance(r[key].get('full_name'), str) and r[key]['full_name'],
                    'missing repository name')
            # Fork runs are never eligible, but do not prevent retaining other records.
        require(r['repository'].get('id') == repo_id and
                r['repository'].get('full_name') == REPOSITORY, 'run repository mismatch')
        require(isinstance(r.get('path'), str) and r['path'], 'missing workflow path')
        require(isinstance(r.get('head_branch'), str) and r['head_branch'], 'missing run branch')
        require(isinstance(r.get('head_sha'), str) and SHA.fullmatch(r['head_sha']), 'invalid run SHA')
        integer(r.get('run_number')); integer(r.get('run_attempt'))
        require(r.get('status') in ('completed', 'queued', 'in_progress', 'waiting',
                                   'pending', 'requested'), 'unknown run status')
        if r['status'] == 'completed':
            require(r.get('conclusion') in ('success', 'failure', 'cancelled', 'skipped',
                    'timed_out', 'action_required', 'neutral', 'stale', 'startup_failure'),
                    'missing run conclusion')
        timestamp(r.get('created_at'), now); timestamp(r.get('updated_at'), now)
    eligible = []
    for a in artifacts.values():
        require(isinstance(a.get('name'), str), 'missing artifact name')
        integer(a.get('size_in_bytes'), 0)
        require(type(a.get('expired')) is bool, 'missing expiry metadata')
        timestamp(a.get('created_at'), now)
        w = a.get('workflow_run')
        require(isinstance(w, dict), 'missing artifact run')
        integer(w.get('repository_id')); integer(w.get('head_repository_id'))
        r = runs.get(integer(w.get('id')))
        require(r is not None, 'artifact run missing from complete history')
        require(w.get('repository_id') == repo_id and
                w.get('head_repository_id') == r['head_repository'].get('id') and
                w.get('head_sha') == r['head_sha'] and w.get('head_branch') == r['head_branch'],
                'artifact/run identity mismatch')
        if (r['head_repository'].get('id') != repo_id or
                r['head_repository'].get('full_name') != REPOSITORY or
                a['expired'] or r['status'] != 'completed'):
            continue
        if (ALPHA_NAME.fullmatch(a['name']) and r['path'] == ALPHA) or (
                a['name'] == 'github-pages' and r['path'] == PAGES and
                r['head_branch'] == branch and r['conclusion'] == 'success'):
            eligible.append(a)
    # Keep the newest completed alpha artifact, regardless of version or branch.
    # Also retain every artifact belonging to that run (including reruns).
    alphas = [a for a in eligible if ALPHA_NAME.fullmatch(a['name'])]
    alpha_keeper = max(alphas, key=lambda a: (timestamp(a['created_at'], now), a['id']), default=None)
    page_runs = [r for r in runs.values() if r['path'] == PAGES]
    active_pages = any(r['status'] != 'completed' for r in page_runs)
    successful_pages = [r for r in page_runs if r['head_branch'] == branch and
                        r['head_repository'].get('id') == repo_id and
                        r['head_repository'].get('full_name') == REPOSITORY and
                        r['status'] == 'completed' and r['conclusion'] == 'success']
    # Preserve both highest source sequence and most recently finished rerun.
    latest_page = max(successful_pages, key=lambda r: (timestamp(r['updated_at'], now), r['id']), default=None)
    highest_page = max((r['run_number'] for r in successful_pages), default=0)
    candidates = []
    for a in eligible:
        r = runs[a['workflow_run']['id']]
        if now - timestamp(a['created_at'], now) < timedelta(days=2):
            continue
        if ALPHA_NAME.fullmatch(a['name']):
            if alpha_keeper is None or r['id'] == alpha_keeper['workflow_run']['id']:
                continue
        else:
            if (active_pages or latest_page is None or r['id'] == latest_page['id'] or
                    r['run_number'] >= highest_page or
                    timestamp(r['updated_at'], now) >= timestamp(latest_page['updated_at'], now)):
                continue
        candidates.append(a)
    candidates.sort(key=lambda a: (timestamp(a['created_at'], now), a['id']))
    require(len(candidates) <= MAX_DELETE, 'deletion limit exceeded; manual review required')
    return candidates


def safe_url(path, method):
    """Never trust URLs returned by GitHub; construct only same-repository paths."""
    root = re.escape(BASE)
    lists = root + r'/actions/(?:artifacts|runs)\?per_page=100&page=[1-9][0-9]*'
    objects = root + r'/actions/(?:artifacts|runs)/[1-9][0-9]*'
    if method == 'GET':
        allowed = path == BASE or re.fullmatch(lists, path) or re.fullmatch(objects, path)
    else:
        allowed = method == 'DELETE' and re.fullmatch(root + r'/actions/artifacts/[1-9][0-9]*', path)
    require(allowed, 'API path or method outside fixed scope')
    return 'https://api.github.com' + path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Unsafe('API redirect refused')


class API:
    def __init__(self, token):
        require(isinstance(token, str) and token, 'GITHUB_TOKEN is required')
        self.token = token
        # Do not forward credentials via environment-configured proxies or redirects.
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def request(self, path, method='GET', missing=False):
        url = safe_url(path, method)
        attempts = 3 if method == 'GET' else 1
        for attempt in range(attempts):
            req = urllib.request.Request(url, method=method, headers={
                'Authorization': 'Bearer ' + self.token,
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28',
                'User-Agent': 'repository-artifact-retention'})
            try:
                with self.opener.open(req, timeout=30) as response:
                    if method == 'DELETE':
                        require(response.status == 204, 'DELETE did not return 204')
                        return None
                    require(response.status == 200, 'GET did not return 200')
                    return json.load(response)
            except urllib.error.HTTPError as exc:
                status = exc.code
                exc.close()
                if method == 'GET' and missing and status == 404:
                    return None
                if method != 'GET' or status not in (429, 500, 502, 503, 504) or attempt == attempts - 1:
                    raise Unsafe('API request failed (HTTP %s); no DELETE retry' % status) from None
            except (urllib.error.URLError, TimeoutError, OSError):
                if method != 'GET' or attempt == attempts - 1:
                    raise Unsafe('API transport failure; no DELETE retry') from None
            time.sleep(2 ** attempt)
        raise Unsafe('GET retry budget exhausted')

    def snapshot(self):
        return dict(repository=self.request(BASE),
                    runs=collection(self.request, '/actions/runs', 'workflow_runs', 999),
                    artifacts=collection(self.request, '/actions/artifacts', 'artifacts', 5000))


def collection(request, endpoint, key, ceiling):
    """Paginate to empty, reconcile declared count, refuse unstable/overlarge sets."""
    rows, total = [], None
    for page in range(1, ceiling + 2):
        data = request(BASE + endpoint + '?per_page=100&page=' + str(page))
        require(isinstance(data, dict), 'invalid collection response')
        count = integer(data.get('total_count'), 0)
        require(count <= ceiling, 'API collection exceeds safety ceiling')
        if total is None:
            total = count
        require(count == total, 'collection changed during pagination')
        batch = data.get(key)
        require(isinstance(batch, list) and len(batch) <= 100, 'invalid page')
        rows.extend(batch)
        unique(rows)
        require(len(rows) <= total, 'collection count overrun')
        if not batch:
            require(len(rows) == total, 'incomplete collection')
            return rows
    raise Unsafe('pagination ceiling reached')


def execute(api, apply=False, clock=lambda: datetime.now(timezone.utc)):
    state = api.snapshot()
    now = clock()
    candidates = plan(state, now)
    report = dict(mode='apply' if apply else 'dry-run', repository=REPOSITORY,
                  observed_at=now.isoformat(), artifact_count=len(state['artifacts']),
                  run_count=len(state['runs']), candidate_count=len(candidates),
                  candidate_bytes=sum(a['size_in_bytes'] for a in candidates),
                  candidates=[dict(id=a['id'], name=a['name'], size_in_bytes=a['size_in_bytes'],
                                   run_id=a['workflow_run']['id']) for a in candidates], deleted_ids=[])
    # Emit before any mutation, without URLs, tokens or arbitrary response bodies.
    print(json.dumps(report, sort_keys=True), flush=True)
    if not apply:
        return report
    for a in candidates:
        # Full fresh history before EVERY DELETE protects current/active Pages and alpha keepers.
        fresh = api.snapshot()
        fresh_plan = plan(fresh, clock())
        match = next((x for x in fresh_plan if x['id'] == a['id']), None)
        require(match == a, 'candidate changed or no longer eligible; stopped')
        artifact_path = BASE + '/actions/artifacts/' + str(a['id'])
        current = api.request(artifact_path)
        require(current == a, 'artifact changed before DELETE')
        rid = a['workflow_run']['id']
        current_run = api.request(BASE + '/actions/runs/' + str(rid))
        listed_run = next(r for r in fresh['runs'] if r['id'] == rid)
        require(current_run == listed_run, 'source run changed before DELETE')
        # DELETE is intentionally never retried, including ambiguous transport failures.
        api.request(artifact_path, method='DELETE')
        require(api.request(artifact_path, missing=True) is None, 'DELETE readback is not 404')
        after = api.snapshot()
        plan(after, clock())  # Validate complete fresh inventory before asserting absence.
        require(all(x['id'] != a['id'] for x in after['artifacts']), 'deleted artifact still listed')
        report['deleted_ids'].append(a['id'])
        print(json.dumps(dict(verified_deleted_id=a['id'])), flush=True)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='delete approved candidates; default is read-only')
    args = parser.parse_args(argv)
    try:
        require(os.environ.get('GITHUB_REPOSITORY', REPOSITORY) == REPOSITORY,
                'repository environment mismatch')
        report = execute(API(os.environ.get('GITHUB_TOKEN')), args.apply)
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a', encoding='utf-8') as stream:
                stream.write('## Artifact retention\n\nMode: %s; inspected %d artifacts / %d runs; '
                             'candidates: %d (%d bytes); verified deletions: %d.\n'
                             'All run records, logs, caches, stable and evidence artifacts are retained.\n' %
                             (report['mode'], report['artifact_count'], report['run_count'],
                              report['candidate_count'], report['candidate_bytes'], len(report['deleted_ids'])))
        print(json.dumps(report, sort_keys=True))
        return 0
    except (Unsafe, KeyError, TypeError, ValueError, StopIteration):
        # Never dump raw API bodies, credential-bearing exceptions or redirect locations.
        print('Artifact cleanup stopped: incomplete, changed or unsafe evidence. No DELETE retry.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
