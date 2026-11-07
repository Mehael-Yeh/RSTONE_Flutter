"""Read-only CI validation of already published APKs, against exact App source.
Uses Android's official aapt/apksigner through the approved source verifier.
Never uses production signing secrets. No emulator/real-device upgrade claim.
"""
from pathlib import Path
from datetime import datetime,timezone
from types import SimpleNamespace
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
sys.dont_write_bytecode=True

API='https://api.github.com/repos/Mehael-Yeh/RSTONE_Flutter'
HEAD='c03ce231a6f3510affda5c0f99a4acb052d952c0'
TREE='8885a244c938a213025bacb3e0d5d537f6670a1b'
TAG='v2.0.14'
def request(url,api=False):
    headers={'Accept':'application/vnd.github+json','User-Agent':'RSTONE-independent-apk-acceptance'}
    if api:headers['Authorization']='Bearer '+os.environ['GH_TOKEN']
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=50) as response:return response.read()
        except Exception:
            if attempt==3:raise RuntimeError('Read-only download failed; no credentials or redirected URL logged') from None
            time.sleep(2**attempt)
def get(path):return json.loads(request(API+path,True))
def sha(data):return hashlib.sha256(data).hexdigest()
def checksum_map(manifest,expected):
    result={}
    for line in manifest.decode('utf-8').splitlines():
        match=re.fullmatch(r'([0-9a-f]{64})  (.+)',line);assert match,'Malformed checksum manifest'
        digest,name=match.groups();assert name not in result,'Duplicate checksum entry';result[name]=digest
    assert set(result)==expected,'Checksum filename set mismatch'
    return result
def resolve(tag):
    obj=get('/git/ref/tags/'+tag)['object']
    for _ in range(4):
        if obj['type']=='commit':return obj['sha']
        assert obj['type']=='tag';obj=get('/git/tags/'+obj['sha'])['object']
    raise AssertionError('Unexpected tag chain')
def download(asset,target):
    assert target.name==asset['name']
    raw=request(asset['browser_download_url'])
    assert len(raw)==asset['size'] and asset['digest']=='sha256:'+sha(raw)
    target.write_bytes(raw)
    return {'name':asset['name'],'size':len(raw),'sha256':sha(raw),'apiDigestMatched':True}

def release_tag(version,alpha=False):
    assert re.fullmatch(r'\d+\.\d+\.\d+',version)
    return 'v'+version+('-alpha' if alpha else '')

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--head',required=True)
    p.add_argument('--baseline',required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--alpha',action='store_true');p.add_argument('--expected-version',required=True);p.add_argument('--source-version',default='2.0.5');a=p.parse_args()
    assert re.fullmatch(r'\d+\.\d+\.\d+',a.expected_version)
    expected_tag=release_tag(a.expected_version,a.alpha)
    source=a.source.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    actual=subprocess.run(['git','rev-parse','HEAD'],cwd=source,check=True,capture_output=True,text=True).stdout.strip()
    assert actual==a.head==HEAD
    tree=subprocess.run(['git','rev-parse','HEAD^{tree}'],cwd=source,check=True,capture_output=True,text=True).stdout.strip()
    assert tree==TREE
    assert not subprocess.run(['git','status','--porcelain','--untracked-files=all'],cwd=source,check=True,capture_output=True,text=True).stdout.strip()
    assert re.search(r'^version:\s*'+re.escape(a.source_version)+r'\+', (source/'pubspec.yaml').read_text(),re.M)
    release=get('/releases/tags/'+expected_tag)
    assert resolve(release['tag_name'])==a.head and release['prerelease'] is a.alpha and not release['draft'],'Exact approved release channel is not available'
    tag=release['tag_name'];assert tag==expected_tag
    m=re.fullmatch(r'v(\d+\.\d+\.\d+)(?:-alpha)?',tag);assert m
    assets={r['name']:r for r in release['assets']}
    expected={f'RSTONE-{tag}{suffix}-{abi}-release.apk' for suffix in ['', '-Lite'] for abi in ['arm64-v8a','armeabi-v7a','x86_64']}
    assert set(assets)==expected|{'SHA256SUMS.txt'} and len(assets)==len(release['assets'])
    current=out/'current';current.mkdir()
    records=[download(assets[name],current/name) for name in sorted(assets)]
    manifest=(current/'SHA256SUMS.txt').read_bytes();manifest_map=checksum_map(manifest,expected)
    assert all(sha((current/name).read_bytes())==manifest_map[name] for name in expected)
    (out/'SHA256SUMS.published.txt').write_bytes(manifest)
    sys.path.insert(0,str(source/'scripts'))
    import verify_release_apks as verifier
    tools=verifier.build_tools_directory()
    baseline_release=get('/releases/tags/'+a.baseline)
    assert a.baseline=='v2.0.13' and baseline_release['tag_name']==a.baseline
    assert not baseline_release['draft'] and not baseline_release['prerelease']
    old_assets={r['name']:r for r in baseline_release['assets']}
    previous=out/'previous';previous.mkdir();baseline=[]
    for suffix in ['', '-Lite']:
        name=f'RSTONE-{a.baseline}{suffix}-arm64-v8a-release.apk';assert name in old_assets
        download(old_assets[name],previous/name);identity=verifier.apk_identity(previous/name,tools)
        assert identity['versionName']=='2.0.13' and identity['abis']==['arm64-v8a']
        baseline.append(identity)
    (out/'baseline-identities.json').write_text(json.dumps(baseline,indent=2)+'\n')
    first=verifier.apk_identity(current/sorted(expected)[0],tools)
    version=m[1]+'+'+str(first['versionCode'])
    old_cwd=Path.cwd();os.chdir(source)
    try:verifier.run(SimpleNamespace(directory=str(current),tag=tag,version=version,build_tools=str(tools),baselines=str(out/'baseline-identities.json')))
    finally:os.chdir(old_cwd)
    assert checksum_map((current/'SHA256SUMS.txt').read_bytes(),expected)==manifest_map
    (current/'SHA256SUMS.txt').write_bytes(manifest)
    identities=[]
    for name in sorted(expected):
        identity=verifier.apk_identity(current/name,tools)
        assert identity['versionName']==m[1]
        identities.append({'name':name,**identity})
    result={'status':'PASS','recordedAt':datetime.now(timezone.utc).isoformat(),'sourceHead':a.head,
        'sourceTree':tree,'checkedInVersion':a.source_version,'qaWorkflowHead':os.environ.get('GITHUB_SHA'),'releaseId':release['id'],'releaseTag':tag,'releaseUrl':release['html_url'],
        'releaseTagResolvedSourceHead':resolve(tag),'version':version,'publishedChecksumSha256':sha(manifest),
        'downloadedAssets':records,'identities':identities,'baselineTag':a.baseline,'baselineIdentities':baseline,
        'androidBuildTools':str(tools),'sixRealApkSignaturesVerifiedByOfficialApksigner':True,
        'pinnedTrustConfigurationAndEditionAssetsVerified':True,'allSixCompatibleIdentityAndIncreasingVersionCode':True,
        'realDeviceOrEmulatorReplacementTestPerformed':False,'osCrossProcessRecoveryTestPerformed':False,
        'printShareTestPerformed':False,'nativeObsidianAcceptance':'USER_CANCELLED_NOT_TESTED',
        'productionSigningKeysUsed':False,'dataSigningPerformed':False}
    (out/'APK_ACCEPTANCE.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':
    try:main()
    except Exception as exc:raise SystemExit('APK acceptance failed: '+type(exc).__name__+' (network URLs redacted)') from None
