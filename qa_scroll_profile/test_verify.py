"""Synthetic validator tests ONLY; these are not Android measurement evidence."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import contextlib
import io
import os
import subprocess
import sys
from unittest.mock import patch
import run_compare as runner
import verify

B = '8c77edb71cd32a287302d5d24d6faed07a3a855d'
C = '1' * 40

SOURCE = '''# SYNTHETIC test lock
packages:
  example:
    dependency: "direct main"
    description:
      name: example
      sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
sdks:
  dart: ">=3.11.0 <4.0.0"
  flutter: ">=3.38.0"
'''
RUNTIME = SOURCE.replace('2.0.0','1.0.0').replace('3.11.0','3.8.1').replace('3.38.0','3.32.8')


def digest(data):
    return hashlib.sha256(data).hexdigest()

class EvidenceTests(unittest.TestCase):
    def fixture(self, root):
        payload = root / 'payload'; payload.mkdir()
        (payload / 'harness.dart').write_text('// SYNTHETIC validator fixture only\n')
        harness = {'harness.dart': digest((payload / 'harness.dart').read_bytes())}
        reports = []
        import run_compare

        for side, sha in [('baseline', B), ('candidate', C)]:
            cases = []
            frame = 0
            for n in [244, 500]:
                for sorted_ in [False, True]:
                    samples = []
                    for repeat in range(3):
                        frame += 1
                        frames = [{'frame': frame, 'build_us': 1000, 'raster_us': 2000, 'total_us': 3000, 'build_start_us': frame * 10000}]
                        samples.append({'repeat': repeat, 'start_us': frame * 10000 - 1, 'end_us': frame * 10000 + 1, 'scroll_ends': 2, 'frames': frames,
                                        'metrics': {'frames': 1, 'build_us': {'p50': 1000, 'p95': 1000, 'p99': 1000}, 'raster_us': {'p50': 2000, 'p95': 2000, 'p99': 2000}, 'over_budget_frames': 0, 'over_budget_ratio': 0.0}})
                    cases.append({'products': n, 'formulas': n, 'sorted': sorted_, 'samples': samples})
            raw = {'schema': 1, 'mode': 'profile', 'source_sha': sha, 'edition': 'full', 'warmups': 2, 'repeats': 3,
                   'view': {'physical_width': 390.0, 'physical_height': 844.0, 'dpr': 1.0, 'refresh_hz': 60.0, 'text_scale': 1.0, 'font': 'QA_YaHei'},
                   'budget_us': 16667, 'gesture': {'dy': -560, 'duration_ms': 800, 'frequency_hz': 60, 'start_offset': 1000}, 'cases': cases}
            data = json.dumps(raw).encode(); (root / (side + '.json')).write_bytes(data)
            source=SOURCE.encode(); runtime=RUNTIME.encode()
            packages=[{'name':'example','version':'1.0.0','source':'hosted'},{'name':'synthetic','version':'1.0.0','source':'root'}]
            graph={'runtime_lock_sha256':digest(runtime),'packages':packages,'configuration':packages}
            deps={'source_lock':run_compare.evidence_file(root,side+'.source.lock',source),
                  'runtime_lock':run_compare.evidence_file(root,side+'.runtime.lock',runtime),
                  'graph':run_compare.evidence_file(root,side+'.graph.json',json.dumps(graph).encode()),
                  'delta':verify.dependency_delta(source,runtime),'compiled_original_pins':False,
                  'runtime_before':digest(runtime),'runtime_after':digest(runtime)}
            reports.append({'dependencies':deps, 'side': side, 'source_sha': sha, 'harness': harness, 'lock_before': digest(source), 'lock_after': digest(source),
                            'raw': {'path': side + '.json', 'sha256': digest(data), 'size': len(data)},
                            'command': ['flutter', 'drive', '--profile', '--no-pub', '--driver=test_driver/qa_scroll_profile_driver.dart', '--target=integration_test/qa_scroll_profile_test.dart', '--flavor', 'full', '--dart-define=RSTONE_LITE=false', '--dart-define=QA_SOURCE_SHA='+sha, '-d', 'emulator-5554'],
                            'renderer': 'Impeller rendering backend (OpenGLES).', 'renderer_evidence': 'Using the Impeller rendering backend (OpenGLES).',
                            'environment': {'font_sha256': 'e'*64, 'api': '35', 'os': 'Android', 'model': 'sdk_gphone64_x86_64', 'flutter': {'frameworkVersion': '3.32.8', 'dartSdkVersion': '3.8.1'}, 'job': 'synthetic-job', 'emulator': 'emulator-5554'}})
        return payload, {'schema': 2, 'qa_source_sha':'a'*40, 'runs': reports}

    def test_valid_synthetic_bundle(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
            root = Path(d); payload, receipt = self.fixture(root)
            result = verify.validate(root, receipt, B, C, payload)
            self.assertEqual(result['scope'], 'Android emulator proxy only; not OPPO PKX110 Android 16')
            self.assertEqual(len(result['comparisons']), 4)

    def mutate_raw(self, root, receipt, mutation):
        entry = receipt['runs'][1]['raw']; p = root / entry['path']; raw = json.loads(p.read_text())
        mutation(raw); data = json.dumps(raw).encode(); p.write_bytes(data)
        entry.update(sha256=digest(data), size=len(data))

    def test_reject_tampering(self):
        mutations = {
            'debug_command': lambda r: r['runs'][1]['command'].__setitem__(2, '--debug'),
            'unbound_renderer': lambda r: r['runs'][1].update(renderer_evidence='Using the fictional rendering backend'),
            'wrong_source': lambda r: r['runs'][1].update(source_sha=B),
            'different_harness': lambda r: r['runs'][1]['harness'].update({'harness.dart': 'f'*64}),
            'lock_changed': lambda r: r['runs'][1].update(lock_after='b'*64),
            'duplicate_run': lambda r: r['runs'].append(copy.deepcopy(r['runs'][0])),
            'missing_run': lambda r: r['runs'].pop(),
            'checksum': lambda r: r['runs'][1]['raw'].update(sha256='f'*64),
            'size': lambda r: r['runs'][1]['raw'].update(size=0),
            'different_emulator': lambda r: r['runs'][1]['environment'].update(emulator='another'),
            'path_traversal': lambda r: r['runs'][1]['raw'].update(path='../outside.json'),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
                root = Path(d); payload, receipt = self.fixture(root); mutate(receipt)
                with self.assertRaises((ValueError, KeyError)):
                    verify.validate(root, receipt, B, C, payload)

    def test_reject_absent_font_identity(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
            root = Path(d); payload, receipt = self.fixture(root)
            for run in receipt['runs']:
                run['environment'].pop('font_sha256')
            with self.assertRaises((ValueError, KeyError)):
                verify.validate(root, receipt, B, C, payload)

    def test_percentiles_and_budget_from_raw(self):
        frames = [{'build_us':n, 'raster_us':n*2} for n in [100,200,300,400,500]]
        result = verify.metrics(frames, 600)
        self.assertEqual(result, {'frames':5, 'build_us':{'p50':300,'p95':500,'p99':500},
            'raster_us':{'p50':600,'p95':1000,'p99':1000}, 'over_budget_frames':2, 'over_budget_ratio':0.4})

    def test_reject_bad_raw_even_rehashed(self):
        mutations = {
            'debug': lambda r: r.update(mode='debug'),
            'source': lambda r: r.update(source_sha=B),
            'empty': lambda r: r['cases'][0]['samples'][0].update(frames=[]),
            'metrics': lambda r: r['cases'][0]['samples'][0]['metrics']['build_us'].update(p99=1),
            'duplicate_case': lambda r: r['cases'].append(copy.deepcopy(r['cases'][0])),
            'missing_case': lambda r: r['cases'].pop(),
            'duplicate_sample': lambda r: r['cases'][0]['samples'].append(copy.deepcopy(r['cases'][0]['samples'][0])),
            'duplicate_frame': lambda r: r['cases'][0]['samples'][0]['frames'].append(copy.deepcopy(r['cases'][0]['samples'][0]['frames'][0])),
            'budget': lambda r: r.update(budget_us=1),
            'no_end': lambda r: r['cases'][0]['samples'][0].update(scroll_ends=0),
            'outside_window': lambda r: r['cases'][0]['samples'][0].update(start_us=999999),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
                root = Path(d); payload, receipt = self.fixture(root); self.mutate_raw(root, receipt, mutate)
                with self.assertRaises((ValueError, KeyError)):
                    verify.validate(root, receipt, B, C, payload)


    def test_runtime_negative_controls(self):
        mutations = {
            'missing_runtime':lambda r:r['runs'][1]['dependencies'].pop('runtime_lock'),
            'runtime_checksum':lambda r:r['runs'][1]['dependencies']['runtime_lock'].update(sha256='f'*64),
            'runtime_size':lambda r:r['runs'][1]['dependencies']['runtime_lock'].update(size=0),
            'duplicate_path':lambda r:r['runs'][1]['dependencies']['runtime_lock'].update(path='baseline.runtime.lock'),
            'traversal':lambda r:r['runs'][1]['dependencies']['runtime_lock'].update(path='../candidate.runtime.lock'),
            'source_checksum':lambda r:r['runs'][1]['dependencies']['source_lock'].update(sha256='f'*64),
            'runtime_drift':lambda r:r['runs'][1]['dependencies'].update(runtime_after='f'*64),
            'false_original_pins':lambda r:r['runs'][1]['dependencies'].update(compiled_original_pins=True),
            'hidden_delta':lambda r:r['runs'][1]['dependencies']['delta'].update(packages=[]),
            'different_sdk':lambda r:r['runs'][1]['environment']['flutter'].update(dartSdkVersion='9.0.0'),
            'both_wrong_sdk':lambda r:[x['environment']['flutter'].update(dartSdkVersion='9.0.0') for x in r['runs']],
            'old_schema':lambda r:r.update(schema=1),
        }
        for name,mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
                root=Path(d); payload,receipt=self.fixture(root); mutation(receipt)
                with self.assertRaises((ValueError,KeyError)):
                    verify.validate(root,receipt,B,C,payload)

    def test_graph_negative_controls(self):
        mutations = {
            'wrong_binding':lambda g:g.update(runtime_lock_sha256='f'*64),
            'wrong_version':lambda g:g['packages'][0].update(version='9.0.0'),
            'wrong_source':lambda g:g['packages'][0].update(source='sdk'),
            'missing_config':lambda g:g.update(configuration=[]),
            'duplicate_package':lambda g:g['packages'].append(copy.deepcopy(g['packages'][0])),
        }
        for name,mutation in mutations.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
                root=Path(d); payload,receipt=self.fixture(root)
                ref=receipt['runs'][1]['dependencies']['graph']; path=root/ref['path']; graph=json.loads(path.read_text())
                mutation(graph); data=json.dumps(graph).encode(); path.write_bytes(data)
                ref.update(sha256=digest(data),size=len(data))
                with self.assertRaises((ValueError,KeyError)):
                    verify.validate(root,receipt,B,C,payload)


    def test_rehashed_runtime_mismatch_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
            root=Path(d); payload,receipt=self.fixture(root); run=receipt['runs'][1]
            dep=run['dependencies']; path=root/dep['runtime_lock']['path']
            data=path.read_bytes()+b'# independently resolved different bytes\n'; path.write_bytes(data)
            dep['runtime_lock'].update(sha256=digest(data),size=len(data))
            dep.update(runtime_before=digest(data),runtime_after=digest(data))
            graphpath=root/dep['graph']['path']; graph=json.loads(graphpath.read_text()); graph['runtime_lock_sha256']=digest(data)
            graphdata=json.dumps(graph).encode(); graphpath.write_bytes(graphdata)
            dep['graph'].update(sha256=digest(graphdata),size=len(graphdata))
            with self.assertRaisesRegex(ValueError,'runtime locks differ'):
                verify.validate(root,receipt,B,C,payload)

    def test_lock_parser_fails_closed(self):
        for data in [SOURCE.replace('source: hosted','source: git'),SOURCE.replace('    version:', '    unexpected:'),SOURCE.replace('sdks:', 'sdks:\n  dart: duplicate'),SOURCE+'unknown: value\n']:
            with self.subTest(lock=data), self.assertRaises(ValueError):
                verify.lock_data(data.encode())


class RunnerTests(unittest.TestCase):
    def scenario(self, fail_drive=False, dirty=False, different_runtime=False, different_source=False, mutate_config=False, fail_pub=False, sdk_drift=False):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
            root = Path(d)
            template = root/'template'; template.mkdir()
            _, seed = EvidenceTests().fixture(template)
            shas=[]
            for i,side in enumerate(['baseline','candidate']):
                app=root/side; app.mkdir()
                for cmd in [['git','init','-q'],['git','config','user.email','synthetic@example.invalid'],['git','config','user.name','Synthetic fixture']]:
                    subprocess.run(cmd,cwd=app,check=True)
                (app/'pubspec.lock').write_text(SOURCE + ('# other source\n' if different_source and i else ''))
                (app/'source.txt').write_text(str(i))
                (app/'assets/fonts').mkdir(parents=True)
                (app/'assets/fonts/MicrosoftYaHei.ttf').write_bytes(b'SYNTHETIC font')
                subprocess.run(['git','add','.'],cwd=app,check=True)
                subprocess.run(['git','commit','-qm','synthetic'],cwd=app,check=True)
                shas.append(subprocess.check_output(['git','rev-parse','HEAD'],cwd=app,text=True).strip())
            original_output=runner.output
            def output(cmd,cwd=None):
                if cmd[0]=='git':
                    if cwd == runner.HERE: return 'a'*40  # synthetic QA checkout identity
                    return original_output(cmd,cwd)
                if cmd[:3]==['flutter','--version','--machine']:
                    return json.dumps({'frameworkVersion':'3.32.8','dartSdkVersion':'9.0.0' if sdk_drift and driven else '3.8.1'})
                if cmd[:4]==['flutter','pub','deps','--json']:
                    return json.dumps({'root':'synthetic','packages':[{'name':'synthetic','version':'1.0.0','source':'root','dependencies':['example']},{'name':'example','version':'1.0.0','source':'hosted','dependencies':[]}]})
                if cmd==['adb','devices']: return 'emulator-5554 device'
                if 'logcat' in cmd: return 'Using the Impeller rendering backend (OpenGLES).'
                if 'getprop' in cmd: return '35' if cmd[-1].endswith('.sdk') else 'SYNTHETIC emulator'
                raise AssertionError(cmd)
            def run(cmd,cwd=None,env=None,log=None):
                if log: log.write_text('SYNTHETIC command stub only\n')
                if cmd[:3]==['flutter','pub','get']:
                    (cwd/'pubspec.lock').write_text(RUNTIME + ('# another runtime\n' if different_runtime and cwd.name=='candidate' else ''))
                    (cwd/'.dart_tool').mkdir()
                    (cwd/'.dart_tool/package_config.json').write_text(json.dumps({'configVersion':2,'packages':[{'name':'synthetic','rootUri':'../','packageUri':'lib/'},{'name':'example','rootUri':'../cache/hosted/pub.dev/example-1.0.0','packageUri':'lib/'}]}))
                    p=cwd/'cache/hosted/pub.dev/example-1.0.0'; p.mkdir(parents=True)
                    (p/'pubspec.yaml').write_text('name: example\nversion: 1.0.0\n')
                    if dirty: (cwd/'source.txt').write_text('unsupported migration')
                    if fail_pub: raise RuntimeError('SYNTHETIC pub get failure after lock write')
                if cmd[:2]==['flutter','drive']:
                    driven.append(cwd.name)
                    if mutate_config: (cwd/'.dart_tool/package_config.json').write_text(json.dumps({'configVersion':2,'packages':[]}))
                    if fail_drive: raise RuntimeError('SYNTHETIC profile failure')
                    raw=json.loads((template/(cwd.name+'.json')).read_text())
                    raw['source_sha']=shas[0 if cwd.name=='baseline' else 1]
                    Path(env['QA_RAW_PATH']).write_text(json.dumps(raw))
            error=None
            driven=[]
            with patch.object(runner,'output',output),patch.object(runner,'run',run),patch.object(sys,'argv',['run_compare.py','--baseline',shas[0],'--candidate',shas[1],'--workspace',str(root)]),patch.dict(os.environ,{'GITHUB_ACTIONS':'true','GITHUB_RUN_ID':'synthetic','GITHUB_RUN_ATTEMPT':'1','GITHUB_JOB':'synthetic'}):
                try:
                    with contextlib.redirect_stdout(io.StringIO()): runner.main()
                except Exception as exc: error=exc
            restored=all((root/s/'pubspec.lock').read_text()==SOURCE+('# other source\n' if different_source and s=='candidate' else '') for s in ['baseline','candidate'])
            receipt=json.loads((root/'evidence/receipt.json').read_text()) if (root/'evidence/receipt.json').exists() else None
            return error,restored,receipt,driven

    def test_source_runtime_differ_but_same_runtime_is_valid(self):
        error,restored,receipt,driven=self.scenario()
        self.assertIsNone(error, str(error))
        self.assertTrue(restored)
        self.assertEqual(receipt['schema'],2)
        self.assertEqual(receipt['runs'][0]['dependencies']['runtime_lock']['sha256'],receipt['runs'][1]['dependencies']['runtime_lock']['sha256'])


    def test_postcompile_configuration_drift_rejected(self):
        error,restored,receipt,driven=self.scenario(mutate_config=True)
        self.assertIsInstance(error,ValueError)
        self.assertTrue(restored)
        self.assertIsNone(receipt)

    def test_sdk_drift_rejected_before_success_receipt(self):
        error,restored,receipt,driven=self.scenario(sdk_drift=True)
        self.assertIsInstance(error,ValueError)
        self.assertTrue(restored)
        self.assertIsNone(receipt)

    def test_pubget_failure_restores_original_lock(self):
        error,restored,receipt,driven=self.scenario(fail_pub=True)
        self.assertIsInstance(error,RuntimeError)
        self.assertTrue(restored)
        self.assertEqual(driven,[])

    def test_failure_restores_original_lock(self):
        error,restored,receipt,driven=self.scenario(fail_drive=True)
        self.assertIsInstance(error,RuntimeError)
        self.assertTrue(restored)
        self.assertIsNone(receipt)

    def test_non_lock_migration_rejected_and_lock_restored(self):
        error,restored,receipt,driven=self.scenario(dirty=True)
        self.assertIsInstance(error,ValueError)
        self.assertIn('non-lock',str(error))
        self.assertTrue(restored)
        self.assertEqual(driven,[])

    def test_different_runtime_rejected_before_candidate_profile(self):
        error,restored,receipt,driven=self.scenario(different_runtime=True)
        self.assertIsInstance(error,ValueError)
        self.assertTrue(restored)
        self.assertEqual(driven,['baseline'])

    def test_different_source_locks_rejected_before_pubget(self):
        error,restored,receipt,driven=self.scenario(different_source=True)
        self.assertIsInstance(error,ValueError)
        self.assertTrue(restored)
        self.assertEqual(driven,[])


class SdkPubspecIdentityTests(unittest.TestCase):
    def check_identity(self, source='sdk', version='0.0.0'):
        import run_compare
        from unittest.mock import patch
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            root=Path(directory); app=root/'app'; sdk=root/'sdk'; (app/'.dart_tool').mkdir(parents=True); (sdk/'bin').mkdir(parents=True)
            location=sdk/'packages/flutter' if source=='sdk' else root/'hosted/pub.dev/flutter-0.0.0'
            location.mkdir(parents=True); (location/'pubspec.yaml').write_text('name: flutter\ndescription: Synthetic versionless SDK fixture\n')
            (app/'.dart_tool/package_config.json').write_text(json.dumps({'configVersion':2,'packages':[{'name':'flutter','rootUri':location.as_uri()}]}))
            packages=[{'name':'flutter','source':source,'version':version}]
            with patch.object(run_compare.shutil,'which',return_value=str(sdk/'bin/flutter')):
                return run_compare.configuration_graph(app,packages)

    def test_versionless_sdk_uses_pub_zero_version(self):
        try:
            actual=self.check_identity()
        except ValueError as error:
            self.fail('Valid versionless SDK package rejected: '+str(error))
        self.assertEqual(actual,[{'name':'flutter','source':'sdk','version':'0.0.0'}])

    def test_versionless_hosted_is_not_sdk_exception(self):
        with self.assertRaises(ValueError): self.check_identity(source='hosted')

    def test_versionless_sdk_cannot_claim_nonzero_version(self):
        with self.assertRaises(ValueError): self.check_identity(version='1.0.0')


if __name__ == '__main__': unittest.main()