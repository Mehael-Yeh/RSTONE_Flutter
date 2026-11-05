"""CI ONLY: sequential exact source checkouts, one already-running emulator."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from verify import package_graph, verify_graph, dependency_delta, digest, harness_hashes, load, metrics, require, SHA, validate

HERE = Path(__file__).resolve().parent

def output(cmd, cwd=None):
    return subprocess.check_output(cmd, cwd=cwd, text=True).strip()

def run(cmd, cwd=None, env=None, log=None):
    if log is None:
        subprocess.run(cmd, cwd=cwd, env=env, check=True)
    else:
        with log.open('w') as stream:
            subprocess.run(cmd, cwd=cwd, env=env, check=True, stdout=stream, stderr=subprocess.STDOUT)


def tracked_clean(app, allow_lock=False):
    paths=output(['git','diff','--name-only','HEAD'],app).splitlines()
    require(not paths or (allow_lock and set(paths)=={'pubspec.lock'}),
            'Unsupported SDK migration/non-lock tracked source change: '+', '.join(paths))

def evidence_file(bundle,name,data):
    p=bundle/name
    require(not p.exists(), 'Refuse duplicate evidence file')
    p.write_bytes(data)
    return {'path':name,'sha256':digest(data),'size':len(data)}

def configuration_graph(app, packages):
    from urllib.parse import urljoin, urlparse, unquote
    config_path=app/'.dart_tool/package_config.json'
    config=load(config_path)
    require(config['configVersion']==2, 'Unsupported package configuration')
    sdk_exe=shutil.which('flutter')
    sdk_root=Path(sdk_exe).resolve().parent.parent if sdk_exe else None
    found=[]
    by_name={p['name']:p for p in packages}
    for item in config['packages']:
        uri=urlparse(urljoin(config_path.as_uri(),item['rootUri']))
        require(uri.scheme=='file' and not uri.netloc, 'Unsupported package config URI')
        location=Path(unquote(uri.path)).resolve()
        p=by_name[item['name']]
        if p['source']=='root':
            require(location==app.resolve(), 'Wrong root package configuration')
            # Root version is not dependency-pinned; pub deps supplies it.
            version=p['version']
        else:
            if p['source']=='sdk':
                require(sdk_root is not None and location.is_relative_to(sdk_root), 'SDK package outside actual Flutter SDK')
            else:
                require('hosted' in location.parts and not location.is_relative_to(app/'lib'), 'Hosted package origin mismatch')
            spec=(location/'pubspec.yaml').read_text()
            names=re.findall(r'^name:\s*[\"\']?([a-zA-Z0-9_]+)[\"\']?\s*$',spec,re.M)
            versions=re.findall(r'^version:\s*[\"\']?([0-9][0-9A-Za-z.+-]*)[\"\']?\s*$',spec,re.M)
            # Pub assigns 0.0.0 to versionless SDK packages (including flutter).
            # Keep this exception confined to the verified SDK root and zero graph version.
            if not versions and p['source']=='sdk' and p['version']=='0.0.0':
                versions=['0.0.0']
            require(names==[p['name']] and len(versions)==1, 'Package pubspec identity unavailable')
            version=versions[0]
        found.append({'name':item['name'],'source':p['source'],'version':version})
    return sorted(found,key=lambda p:p['name'])

@contextmanager
def runtime_session(app,bundle,side):
    lock=app/'pubspec.lock'; source=lock.read_bytes()
    source_ref=evidence_file(bundle,side+'.source.lock',source)
    try:
        run(['flutter','pub','get'],app,log=bundle/(side+'.pub.log'))
        tracked_clean(app,True)
        runtime=lock.read_bytes()
        runtime_ref=evidence_file(bundle,side+'.runtime.lock',runtime)
        packages=package_graph(json.loads(output(['flutter','pub','deps','--json'],app)))
        graph={'runtime_lock_sha256':digest(runtime),'packages':packages,'configuration':configuration_graph(app,packages)}
        verify_graph(runtime,graph)
        require(lock.read_bytes()==runtime,'pub deps changed resolved lock')
        graph_ref=evidence_file(bundle,side+'.graph.json',(json.dumps(graph,sort_keys=True,indent=2)+'\n').encode())
        dependency={'source_lock':source_ref,'runtime_lock':runtime_ref,'graph':graph_ref,
                    'delta':dependency_delta(source,runtime),'compiled_original_pins':source==runtime,
                    'runtime_before':digest(runtime)}
        yield dependency
        require(configuration_graph(app,packages)==graph['configuration'], 'Compiled package configuration changed')
        require(package_graph(json.loads(output(['flutter','pub','deps','--json'],app)))==packages, 'Compiled package graph changed')
        require(lock.read_bytes()==runtime, 'Profile build changed actual runtime lock')
        dependency['runtime_after']=digest(lock.read_bytes())
        tracked_clean(app,True)
    finally:
        lock.write_bytes(source)
        require(lock.read_bytes()==source,'Original source lock restoration failed')
        tracked_clean(app)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', required=True); parser.add_argument('--candidate', required=True)
    parser.add_argument('--workspace', required=True, type=Path)
    args = parser.parse_args()
    require(SHA.fullmatch(args.baseline) and SHA.fullmatch(args.candidate) and args.baseline != args.candidate, 'Distinct 40hex sources required')
    require(os.environ.get('GITHUB_ACTIONS') == 'true', 'CI only; do not run against a real workstation/device')
    root = args.workspace.resolve(); bundle = root / 'evidence'; bundle.mkdir(exist_ok=False)
    payload = HERE / 'payload'; harness = harness_hashes(payload)
    flutter = json.loads(output(['flutter','--version','--machine']))
    adb = ['adb','-s','emulator-5554']
    require('emulator-5554' in output(['adb','devices']), 'Expected existing emulator')
    run(adb+['shell','wm','size','390x844']); run(adb+['shell','wm','density','160'])
    environment = {'flutter':flutter, 'api':output(adb+['shell','getprop','ro.build.version.sdk']),
                   'os':output(adb+['shell','getprop','ro.build.version.release']),
                   'model':output(adb+['shell','getprop','ro.product.model']),
                   'job':os.environ['GITHUB_RUN_ID']+':'+os.environ['GITHUB_RUN_ATTEMPT']+':'+os.environ['GITHUB_JOB'], 'emulator':'emulator-5554'}
    receipt = {'schema':2, 'runs':[], 'qa_source_sha':output(['git','rev-parse','HEAD'],HERE)}
    originals = [(root/side/'pubspec.lock').read_bytes() for side in ['baseline','candidate']]
    require(originals[0] == originals[1], 'Original source locks differ; unsupported comparison')
    for side, sha in [('baseline',args.baseline),('candidate',args.candidate)]:
        app = root / side
        require(output(['git','rev-parse','HEAD'],app) == sha, 'Checkout not exact source')
        require(output(['git','status','--porcelain'],app) == '', 'Source checkout already modified')
        require(not (app/'android/key.properties').exists(), 'Production signing configuration forbidden')
        side_environment = dict(environment, font_sha256=digest((app/'assets/fonts/MicrosoftYaHei.ttf').read_bytes()))
        lock_before = digest((app/'pubspec.lock').read_bytes())
        for name in harness:
            source = payload / name; target = app / name
            require(not target.exists(), 'Refuse to overwrite source file: '+name)
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(source,target)
        require({n:digest((app/n).read_bytes()) for n in harness} == harness, 'Injection changed')
        with runtime_session(app,bundle,side) as dependency:
            if receipt['runs']:
                require(dependency['runtime_lock']['sha256']==receipt['runs'][0]['dependencies']['runtime_lock']['sha256'], 'Actual runtime locks differ; unsupported comparison')
            require(json.loads(output(['flutter','--version','--machine']))==flutter, 'Actual SDK changed before compilation')
            # No production entrypoint, signing secrets, sync, publish command or production APK upload.
            run(adb+['logcat','-c'])
            env = dict(os.environ, QA_RAW_PATH=str(bundle/(side+'.json')))
            cmd = ['flutter','drive','--profile','--no-pub','--driver=test_driver/qa_scroll_profile_driver.dart',
                   '--target=integration_test/qa_scroll_profile_test.dart','--flavor','full',
                   '--dart-define=RSTONE_LITE=false','--dart-define=QA_SOURCE_SHA='+sha,'-d','emulator-5554']
            run(cmd,app,env,bundle/(side+'.drive.log'))
            require(json.loads(output(['flutter','--version','--machine']))==flutter, 'Actual SDK changed during compilation')
            engine = output(adb+['logcat','-d','-s','flutter'])
            (bundle/(side+'.renderer.log')).write_text(engine)
            evidence = re.findall(r'Using the ([^\r\n]+rendering backend[^\r\n]*)',engine+'\n'+(bundle/(side+'.drive.log')).read_text())
            require(bool(evidence), 'Actual renderer unavailable: unsupported; do not guess it')
            renderer = evidence[-1].strip()
            raw_path = bundle/(side+'.json'); raw = load(raw_path)
            for case in raw['cases']:
                for sample in case['samples']:
                    sample['metrics'] = metrics(sample['frames'],raw['budget_us'])
            raw_path.write_text(json.dumps(raw,sort_keys=True,indent=2)+'\n')
            data = raw_path.read_bytes()
        lock_after = digest((app/'pubspec.lock').read_bytes())
        tracked_clean(app)
        entry = {'side':side, 'source_sha':sha, 'harness':{n:digest((app/n).read_bytes()) for n in harness},
                 'lock_before':lock_before,'lock_after':lock_after,'dependencies':dependency,'environment':side_environment,
                 'renderer':renderer,'renderer_evidence':'Using the '+renderer,
                 'command':cmd,'raw':{'path':raw_path.name,'size':len(data),'sha256':digest(data)}}
        receipt['runs'].append(entry)
        (bundle/'receipt.json').write_text(json.dumps(receipt,sort_keys=True,indent=2)+'\n')
    result = validate(bundle,receipt,args.baseline,args.candidate,payload)
    (bundle/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('UNSUPPORTED_OR_FAILED: '+str(exc),file=sys.stderr)
        raise