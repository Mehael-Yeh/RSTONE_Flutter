"""Fail-closed stdlib verifier. Raw frame times are measured, never simulated here."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

SHA = re.compile(r'[0-9a-f]{40}\Z')
HEX = re.compile(r'[0-9a-f]{64}\Z')

def require(condition, message):
    if not condition:
        raise ValueError(message)

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result

def load(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=unique_object,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def harness_hashes(payload):
    files = sorted(p for p in Path(payload).rglob('*') if p.is_file())
    require(bool(files), 'Empty payload')
    require(not any(p.is_symlink() for p in files), 'Symlink payload')
    return {str(p.relative_to(payload)): digest(p.read_bytes()) for p in files}

def metrics(frames, budget):
    require(bool(frames), 'No FrameTiming data: unsupported')
    result = {'frames': len(frames)}
    for field in ['build_us', 'raster_us']:
        values = sorted(f[field] for f in frames)
        require(all(type(v) is int and v >= 0 for v in values), 'Invalid timing')
        result[field] = {'p'+str(p): values[math.ceil(len(values)*p/100)-1] for p in [50,95,99]}
    over = sum(max(f['build_us'], f['raster_us']) > budget for f in frames)
    result.update(over_budget_frames=over, over_budget_ratio=over/len(frames))
    return result

# Deliberately restricted parser for pub-generated lock mappings, NOT general YAML.
# Unsupported syntax or package sources fail closed rather than silently dropping fields.
def lock_data(data):
    text = data.decode('utf-8')
    result = {}; stack = [(-2, result)]
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'): continue
        m = re.fullmatch(r'( *)([A-Za-z0-9_]+):(?: (.*))?', line)
        require(m is not None, 'Unsupported lock YAML syntax')
        indent, key, value = len(m[1]), m[2], m[3]
        while stack[-1][0] >= indent: stack.pop()
        require(indent == stack[-1][0]+2, 'Unsupported lock indentation')
        parent = stack[-1][1]
        require(key not in parent, 'Duplicate lock key')
        if value is None:
            parent[key] = {}; stack.append((indent,parent[key])); continue
        if value.startswith('"'):
            value = json.loads(value)
        elif value.startswith("'"):
            require(value.endswith("'"), 'Unsupported quoted scalar')
            value = value[1:-1].replace("''", "'")
        else:
            require(re.fullmatch(r'[A-Za-z0-9_.+<>=^ /:-]+',value) is not None, 'Unsupported lock scalar')
        require(isinstance(value,str), 'Lock scalar must be text')
        parent[key] = value
    require(set(result) == {'packages','sdks'}, 'Unsupported lock layout')
    require(isinstance(result['packages'],dict) and result['packages'], 'Empty lock graph')
    require(set(result['sdks']) <= {'dart','flutter'} and 'dart' in result['sdks'], 'Unsupported SDK requirements')
    for name,p in result['packages'].items():
        require(isinstance(p,dict) and set(p)=={'dependency','description','source','version'}, 'Unsupported package fields')
        require(p['source'] in ['hosted','sdk'], 'Unsupported dependency source: '+str(p['source']))
        require(re.fullmatch(r'\d+\.\d+\.\d+(?:[-+][A-Za-z0-9_.+-]+)?',p['version']) is not None, 'Unsupported package version')
        if p['source']=='hosted':
            desc=p['description']
            require(isinstance(desc,dict) and set(desc)=={'name','sha256','url'} and desc['name']==name and HEX.fullmatch(desc['sha256']) and desc['url'].startswith('https://'), 'Unsupported hosted description')
        else:
            require(p['description']=='flutter', 'Unsupported SDK package origin')
    return result

def dependency_delta(source, runtime):
    a,b = lock_data(source),lock_data(runtime)
    return {'packages':[{'name':n,'original':a['packages'].get(n),'resolved':b['packages'].get(n)}
                        for n in sorted(set(a['packages'])|set(b['packages'])) if a['packages'].get(n)!=b['packages'].get(n)],
            'original_sdk_constraints':a['sdks'], 'resolved_sdk_constraints':b['sdks']}

def package_graph(deps):
    require(isinstance(deps.get('packages'),list), 'Missing pub deps graph')
    packages=[]; seen=set()
    for p in deps['packages']:
        require(p['name'] not in seen, 'Duplicate graph package'); seen.add(p['name'])
        require(p['source'] in ['root','hosted','sdk'], 'Unsupported graph source')
        packages.append({k:p[k] for k in ['name','version','source']})
    return sorted(packages,key=lambda p:p['name'])

def verify_graph(runtime, graph):
    lock=lock_data(runtime)
    require(set(graph)=={'runtime_lock_sha256','packages','configuration'}, 'Graph schema')
    require(graph['runtime_lock_sha256']==digest(runtime), 'Graph runtime lock binding mismatch')
    packages=graph['packages']; config=graph['configuration']
    require(packages==sorted(packages,key=lambda p:p['name']) and len({p['name'] for p in packages})==len(packages), 'Duplicate/unsorted graph')
    require(config==packages, 'Package configuration does not match compiled graph')
    roots=[p for p in packages if p['source']=='root']
    require(len(roots)==1, 'Missing/duplicate graph root')
    actual={p['name']:{'version':p['version'],'source':p['source']} for p in packages if p['source']!='root'}
    expected={n:{'version':p['version'],'source':p['source']} for n,p in lock['packages'].items()}
    require(actual==expected, 'Runtime lock/package graph mismatch')

def read_evidence(root, ref, expected, used):
    require(set(ref)=={'path','size','sha256'}, 'Evidence reference schema')
    name=ref['path']
    require(name==expected and re.fullmatch(r'[a-z][a-z0-9_.-]*',name) and name not in used, 'Unsafe/duplicate evidence path')
    used.add(name); path=root/name
    require(not path.is_symlink() and path.resolve().parent==root, 'Unsafe evidence file')
    data=path.read_bytes()
    require(type(ref['size']) is int and len(data)==ref['size'] and digest(data)==ref['sha256'], 'Evidence size/checksum mismatch')
    return data

def verify_dependencies(root, run, used):
    d=run['dependencies']; side=run['side']
    require(set(d)=={'source_lock','runtime_lock','graph','delta','compiled_original_pins','runtime_before','runtime_after'}, 'Missing dependency evidence')
    source=read_evidence(root,d['source_lock'],side+'.source.lock',used)
    runtime=read_evidence(root,d['runtime_lock'],side+'.runtime.lock',used)
    graph_data=read_evidence(root,d['graph'],side+'.graph.json',used)
    graph=json.loads(graph_data,object_pairs_hook=unique_object)
    require(run['lock_before']==digest(source)==run['lock_after'], 'Original source lock drift')
    require(d['runtime_before']==digest(runtime)==d['runtime_after'], 'Compiled runtime lock drift')
    require(d['delta']==dependency_delta(source,runtime), 'Undisclosed original/runtime lock delta')
    require(type(d['compiled_original_pins']) is bool and d['compiled_original_pins']==(source==runtime), 'False original production pins claim')
    verify_graph(runtime,graph)
    return {'source_lock_sha256':digest(source),'runtime_lock_sha256':digest(runtime),
            'compiled_original_pins':source==runtime,'delta':d['delta']}

def validate(root, receipt, baseline, candidate, payload):
    root = Path(root).resolve()
    require(SHA.fullmatch(baseline) and SHA.fullmatch(candidate) and baseline != candidate, 'Distinct exact 40hex sources required')
    require(receipt['schema'] == 2, 'Receipt schema')
    runs = receipt['runs']
    require(len(runs) == 2 and [r['side'] for r in runs] == ['baseline','candidate'], 'Missing/duplicate/order of runs')
    expected_harness = harness_hashes(Path(payload))
    loaded = []; dependencies = []; used = set()
    require(SHA.fullmatch(receipt['qa_source_sha']), 'Missing exact QA tool source')
    for run, expected in zip(runs, [baseline,candidate]):
        require(run['source_sha'] == expected, 'Wrong source SHA')
        require(run['harness'] == expected_harness, 'Harness bytes not identical to trusted payload')
        require(HEX.fullmatch(run['lock_before']) and run['lock_before'] == run['lock_after'], 'Dependency lock changed')
        dependencies.append(verify_dependencies(root,run,used))
        raw_ref = run['raw']; path = root / raw_ref['path']
        require(not path.is_symlink() and path.resolve().parent == root and path.name in ['baseline.json','candidate.json'], 'Unsafe raw path')
        require(path.name == run['side']+'.json', 'Raw side mismatch')
        data = path.read_bytes()
        require(len(data) == raw_ref['size'] and digest(data) == raw_ref['sha256'], 'Raw size/checksum mismatch')
        raw = load(path)
        require(raw['schema'] == 1 and raw['source_sha'] == expected and raw['mode'] == 'profile', 'Not exact source AOT profile')
        require(raw['edition'] == 'full' and raw['warmups'] == 2 and raw['repeats'] == 3, 'Protocol changed')
        require(raw['gesture'] == {'dy':-560,'duration_ms':800,'frequency_hz':60,'start_offset':1000}, 'Gesture changed')
        view = raw['view']; hz = view['refresh_hz']
        require(isinstance(hz,(int,float)) and math.isfinite(hz) and hz > 0, 'Display refresh unavailable')
        require(view['text_scale'] == 1 and view['font'] == 'QA_YaHei', 'Font/scale changed')
        require(all(view[k] > 0 for k in ['physical_width','physical_height','dpr']), 'Invalid view')
        require(raw['budget_us'] == math.floor(1000000/hz+0.5), 'Budget not based on recorded display refresh')
        require(run['renderer'] and run['renderer_evidence'] == 'Using the '+run['renderer'] and 'rendering backend' in run['renderer'], 'Renderer evidence not bound')
        require(run['command'] == ['flutter','drive','--profile','--no-pub','--driver=test_driver/qa_scroll_profile_driver.dart',
                '--target=integration_test/qa_scroll_profile_test.dart','--flavor','full','--dart-define=RSTONE_LITE=false',
                '--dart-define=QA_SOURCE_SHA='+expected,'-d','emulator-5554'], 'Not exact profile command')
        env = run['environment']
        require(HEX.fullmatch(env['font_sha256']), 'Missing actual font identity')
        require(env['api'] == '35' and env['flutter']['frameworkVersion'] == '3.32.8' and re.fullmatch(r'3\.8\.1(?: \(.*\))?',env['flutter']['dartSdkVersion']), 'Unapproved API/Flutter/Dart')
        require(all(env[k] for k in ['os','model','job','emulator']) and env['flutter']['dartSdkVersion'], 'Missing environment')
        require([(c['products'],c['formulas'],c['sorted']) for c in raw['cases']] == [(244,244,False),(244,244,True),(500,500,False),(500,500,True)], 'Missing/duplicate cases')
        seen_frames = set()
        for case in raw['cases']:
            require([s['repeat'] for s in case['samples']] == [0,1,2], 'Missing/duplicate repeats')
            for sample in case['samples']:
                require(sample['start_us'] < sample['end_us'] and sample['scroll_ends'] >= 2, 'Scroll end not captured')
                for frame in sample['frames']:
                    require(type(frame['frame']) is int and frame['frame'] not in seen_frames, 'Duplicate frame')
                    seen_frames.add(frame['frame'])
                    require(sample['start_us'] <= frame['build_start_us'] <= sample['end_us'], 'Frame outside recorded window')
                    require(type(frame['total_us']) is int and frame['total_us'] >= max(frame['build_us'],frame['raster_us']), 'Invalid total time')
                require(sample['metrics'] == metrics(sample['frames'], raw['budget_us']), 'Metrics differ from raw timings')
        loaded.append(raw)
    require(runs[0]['environment'] == runs[1]['environment'], 'Not same emulator/job/toolchain')
    require(runs[0]['renderer'] == runs[1]['renderer'], 'Renderer changed')
    require(runs[0]['lock_before'] == runs[1]['lock_before'], 'Dependency locks differ between sources: cannot isolate fix')
    require(dependencies[0]['runtime_lock_sha256']==dependencies[1]['runtime_lock_sha256'], 'Actual runtime locks differ')
    require(loaded[0]['view'] == loaded[1]['view'], 'View/refresh/font changed')
    comparisons = []
    for a,b in zip(loaded[0]['cases'],loaded[1]['cases']):
        item = {'products':a['products'], 'sorted':a['sorted']}
        for side, case, raw in [('baseline',a,loaded[0]),('candidate',b,loaded[1])]:
            item[side] = metrics([f for s in case['samples'] for f in s['frames']],raw['budget_us'])
        comparisons.append(item)
    return {'scope':'Android emulator proxy only; not OPPO PKX110 Android 16', 'baseline':baseline, 'candidate':candidate,
            'budget_us':loaded[0]['budget_us'], 'view':loaded[0]['view'], 'environment':runs[0]['environment'],
            'renderer':runs[0]['renderer'], 'comparisons':comparisons, 'dependencies':dependencies,
            'warning':'Sequential baseline then candidate; emulator/GPU/thermal/order noise remains. No real-device FPS or touch-latency conclusion.'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle',type=Path); parser.add_argument('--baseline',required=True); parser.add_argument('--candidate',required=True)
    parser.add_argument('--payload',required=True,type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.bundle,load(args.bundle/'receipt.json'),args.baseline,args.candidate,args.payload),indent=2))