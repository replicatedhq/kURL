"""Publish an isolated test-only version; never update staging/VERSION or shared metadata."""
import json, pathlib, re, subprocess, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
CONFIG = json.loads((HERE / 'config.json').read_text())
BASE, VERSION = CONFIG['base'], CONFIG['isolated']
assert VERSION == 'v2026.09.20-0-rc-rook-27348763f'
PREFIX = 'staging/' + VERSION + '/'
SOURCE = 'staging/' + BASE + '/'
BUCKET = 'kurl-sh'
URL = 'https://kurl-sh.s3.amazonaws.com/'
PACKAGES = ['common.tar.gz', 'host-openssl.tar.gz', 'host-fio.tar.gz',
            'kubernetes-1.34.11.tar.gz', 'kubernetes-conformance-1.34.11.tar.gz',
            'flannel-0.28.9.tar.gz', 'containerd-2.3.3.tar.gz', 'containerd-2.2.6.tar.gz',
            'minio-2025-10-15T17-29-55Z.tar.gz', 'ekco-0.28.16.tar.gz',
            'sonobuoy-0.57.3.tar.gz', 'rook-1.18.11.tar.gz', 'rook-1.19.7.tar.gz']

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'curl/8.7.1'}), timeout=90).read()

def probe(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={'Range':'bytes=0-0','User-Agent':'curl/8.7.1'}), timeout=90) as response:
        assert response.status in (200,206), url
        response.read(1)

def aws(*args):
    return subprocess.check_output(['aws', 's3api', *args], text=True)

def copy(source, target):
    assert source.startswith(SOURCE) and target.startswith(PREFIX)
    aws('copy-object', '--bucket', BUCKET, '--copy-source', BUCKET+'/'+source, '--key', target)
    before=json.loads(aws('head-object','--bucket',BUCKET,'--key',source))
    after=json.loads(aws('head-object','--bucket',BUCKET,'--key',target))
    assert before['ContentLength']==after['ContentLength'], target
    probe(URL+target)

def put(name, data, content_type):
    path=HERE/('upload-'+name); path.write_bytes(data)
    aws('put-object','--bucket',BUCKET,'--key',PREFIX+name,'--body',str(path),'--content-type',content_type)
    assert get(URL+PREFIX+name)==data

probe(CONFIG['candidate'])
metadata=json.loads(get(URL+SOURCE+'supported-versions-gen.json'))
assert '1.19.7' in metadata['supportedVersions']['rook']
metadata['supportedVersions']['rook'] = ['1.20.8'] + [v for v in metadata['supportedVersions']['rook'] if v!='1.20.8']
for name in PACKAGES:
    probe(URL+SOURCE+name)
    copy(SOURCE+name, PREFIX+name)
# API picks the versioned bin-utils filename; alias identical published bytes.
copy(SOURCE+'kurl-bin-utils-'+BASE+'.tar.gz', PREFIX+'kurl-bin-utils-'+VERSION+'.tar.gz')
for name in ['install.tmpl','join.tmpl','upgrade.tmpl','tasks.tmpl']:
    text=get(URL+SOURCE+name).decode()
    text,count=re.subn(r'^KURL_UTIL_IMAGE=.*$', 'KURL_UTIL_IMAGE="replicated/kurl-util:'+BASE+'"',text,flags=re.M)
    assert count==1, name
    # Everything else, including API-injected step lists and versioned URLs, stays unchanged.
    put(name,text.encode(),'text/plain')
# Publish metadata last so this isolated prefix becomes usable only after closure is ready.
put('supported-versions-gen.json',(json.dumps(metadata,indent=2)+'\n').encode(),'application/json')
print('Verified isolated prefix:',PREFIX,'(14 copied packages,4 templates,1 metadata object)')
