"""Verify installer rendering and package availability before enqueueing existing scenarios."""
import json,pathlib,re,urllib.request
HERE=pathlib.Path(__file__).resolve().parent
CONFIG=json.loads((HERE/'config.json').read_text())
SPECS=json.loads((HERE/'rook.json').read_text())
assert len(SPECS)==4 and sum(bool(i.get('airgap')) for i in SPECS)==1
urls=[]
for case in SPECS:
    for field in ['installerSpec','upgradeSpec']:
        if field not in case:continue
        spec=case[field]
        body=json.dumps({'apiVersion':'cluster.kurl.sh/v1beta1','kind':'Installer','metadata':{'name':'test'},'spec':spec}).encode()
        request=urllib.request.Request('https://staging.kurl.sh/installer',data=body,headers={'Content-Type':'text/yaml','User-Agent':'curl/8.7.1'})
        url=urllib.request.urlopen(request,timeout=90).read().decode().strip()
        assert url.startswith('https://staging.kurl.sh/'),url
        script=urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'curl/8.7.1'}),timeout=90).read().decode()
        version=spec['kurl']['installerVersion']
        assert 'KURL_VERSION="'+version+'"' in script
        assert 'KURL_UTIL_IMAGE="replicated/kurl-util:'+CONFIG['base']+'"' in script
        if field=='upgradeSpec':
            versions=re.search(r'^ROOK_STEP_VERSIONS=\(([^)]+)\)',script,re.M).group(1).split()
            assert len(versions)==21 and versions[18:]==['1.18.11','1.19.7','1.20.7'],versions
        if spec['rook']['version']=='1.20.7':assert CONFIG['candidate'] in script
        # Verify externally resolved KOTS URL and any explicit candidate override by real GET.
        for external in set(re.findall(r'^    s3Override: (https?://\S+)',script,re.M)):
            external=external.strip('"')
            with urllib.request.urlopen(urllib.request.Request(external,headers={'Range':'bytes=0-0','User-Agent':'curl/8.7.1'}),timeout=90) as r:r.read(1)
        urls.append({'case':case['name'],'phase':field,'url':url,'version':version})
(HERE/'verified-installers.json').write_text(json.dumps(urls,indent=2))
print(json.dumps(urls,indent=2))
