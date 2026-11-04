"""Exact successful Web artifact versus real anonymous Pages bytes, in read-only CI."""
from pathlib import Path
from datetime import datetime,timezone
import argparse
import hashlib
import io
import json
import os
import tarfile
import urllib.error
import urllib.request
import zipfile

API='https://api.github.com/repos/Mehael-Yeh/RSTONE_Flutter'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def req(url,authenticated=False):
    headers={'User-Agent':'RSTONE-independent-web-acceptance','Cache-Control':'no-cache'}
    if authenticated:headers['Authorization']='Bearer '+os.environ['GH_TOKEN']
    return urllib.request.Request(url,headers=headers)
def api(path):
    with urllib.request.urlopen(req(API+path,True),timeout=50) as r:return json.load(r)
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,request,fp,code,msg,headers,newurl):return None

def main():
    p=argparse.ArgumentParser();p.add_argument('--run',type=int,required=True);p.add_argument('--head',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True)
    run=api('/actions/runs/'+str(a.run));assert run['head_sha']==a.head and run['conclusion']=='success' and run['status']=='completed'
    objects=api('/actions/runs/'+str(a.run)+'/artifacts?per_page=100');assert len(objects['artifacts'])==objects['total_count']
    artifacts=[r for r in objects['artifacts'] if r['name']=='github-pages' and not r['expired']];assert len(artifacts)==1
    artifact=artifacts[0];assert artifact['workflow_run']['head_sha']==a.head
    opener=urllib.request.build_opener(NoRedirect)
    try:
        opener.open(req(API+'/actions/artifacts/'+str(artifact['id'])+'/zip',True),timeout=50)
        raise AssertionError('Expected isolated signed redirect')
    except urllib.error.HTTPError as e:
        assert e.code==302;location=e.headers['Location']
    with urllib.request.urlopen(req(location),timeout=120) as r:raw=r.read()
    if artifact.get('digest'):assert artifact['digest']=='sha256:'+sha(raw)
    names={'index.html','main.dart.js','flutter_bootstrap.js','version.json','assets/assets/data_sync_config.json'};files={}
    with zipfile.ZipFile(io.BytesIO(raw)) as outer:
        assert outer.namelist()==['artifact.tar']
        with tarfile.open(fileobj=io.BytesIO(outer.read('artifact.tar')),mode='r:*') as tar:
            for member in tar:
                name=member.name.removeprefix('./')
                if name in names:
                    assert member.isfile();files[name]=tar.extractfile(member).read()
    assert set(files)==names and b'rstone-recipe/1' in files['main.dart.js']
    site='https://mehael-yeh.github.io/RSTONE_Flutter/';checked=[]
    for name,expected in files.items():
        with urllib.request.urlopen(req(site+name+'?acceptance='+a.head[:12]),timeout=60) as r:live=r.read()
        checked.append({'path':name,'bytes':len(expected),'artifactSha256':sha(expected),'liveSha256':sha(live),'matched':expected==live})
    result={'status':'PASS' if all(r['matched'] for r in checked) else 'FAIL','recordedAt':datetime.now(timezone.utc).isoformat(),
        'sourceHead':a.head,'runId':a.run,'runUrl':run['html_url'],'artifactId':artifact['id'],'artifactZipSha256':sha(raw),
        'apiArtifactDigest':artifact.get('digest'),'anonymousProductionUrl':site,'files':checked,'structuredProtocolMarker':True,
        'performedFrom':'independent GitHub Actions Linux runner','authenticatedHeadersUsedForPublicPages':False,
        'signedRedirectStoredOrLogged':False,'dataSigningPerformed':False}
    (a.output/'WEB_ACCEPTANCE.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2));assert result['status']=='PASS'
if __name__=='__main__':main()
