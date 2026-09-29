import base64,gzip,hashlib,io,json,os,pathlib,ssl,subprocess,tarfile,time,urllib.error,urllib.parse,urllib.request
import yaml
BACKEND=os.environ.get('BACKEND','pvc')
ROOT=pathlib.Path(os.environ['RUNNER_TEMP'])/'registry-smoke'
ROOT.mkdir(exist_ok=True)
for d in ['pki','auth','config','data']: (ROOT/d).mkdir(exist_ok=True)
USER='test';PASSWORD='ephemeral-test-password'
AUTH='Basic '+base64.b64encode(f'{USER}:{PASSWORD}'.encode()).decode()
subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(ROOT/'pki/registry.key'),'-out',str(ROOT/'pki/registry.crt'),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
with (ROOT/'auth/htpasswd').open('w') as f: subprocess.run(['htpasswd','-Bbn',USER,PASSWORD],check=True,stdout=f)
context=ssl.create_default_context(cafile=str(ROOT/'pki/registry.crt'))
url='https://localhost:5443'
def request(path,method='GET',data=None,headers=None,auth=True,expected=200):
 h=dict(headers or {})
 if auth:h['Authorization']=AUTH
 req=urllib.request.Request(url+path,data=data,headers=h,method=method)
 try:r=urllib.request.urlopen(req,context=context,timeout=20)
 except urllib.error.HTTPError as e:r=e
 body=r.read()
 assert r.status==expected,(method,path,r.status,body[:300])
 return r.headers,body

def start(version):
 filename='tmpl-deployment-objectstore.yaml' if BACKEND=='s3' else 'deployment-pvc.yaml'
 docs=list(yaml.safe_load_all(pathlib.Path(f'addons/registry/{version}/{filename}').read_text().replace('$objectStoreIP','minio-smoke:9000')))
 config=next(d['data']['config.yml'] for d in docs if d['kind']=='ConfigMap')
 (ROOT/'config/config.yml').write_text(config)
 deployment=next(d for d in docs if d['kind']=='Deployment')
 container=deployment['spec']['template']['spec']['containers'][0]
 assert container['image']==f'registry:{version}'
 args=['docker','run','-d','--name','registry-smoke','-p','127.0.0.1:5443:443','-e','REGISTRY_HTTP_SECRET=ephemeral-test-secret','-e','OTEL_TRACES_EXPORTER=none']
 for a,b in [('pki','/etc/pki'),('auth','/auth'),('config','/etc/docker/registry'),('data','/var/lib/registry')]:args+=['-v',f'{ROOT/a}:{b}']
 if BACKEND=='s3':args+=['--network','registry-smoke','-e','AWS_ACCESS_KEY_ID=smokeuser','-e','AWS_SECRET_ACCESS_KEY=smokepassword']
 args+=['--entrypoint',container['command'][0],container['image']]+container['command'][1:]
 subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
 for i in range(60):
  try:request('/v2/');break
  except (OSError,AssertionError):time.sleep(1)
 else:raise RuntimeError('registry did not become ready')
 request('/v2/',auth=False,expected=401)
 print(f'PASS {version}: starts with actual add-on {BACKEND} config; TLS verified; unauthenticated access rejected',flush=True)

def stop():subprocess.run(['docker','rm','-f','registry-smoke'],check=True,stdout=subprocess.DEVNULL)
def digest(data):return 'sha256:'+hashlib.sha256(data).hexdigest()
def push_blob(data):
 dg=digest(data)
 headers,_=request('/v2/smoke/blobs/uploads/','POST',b'',expected=202)
 location=headers['Location'];parts=urllib.parse.urlsplit(location)
 path=parts.path+'?'+parts.query+('&' if parts.query else '')+'digest='+dg
 request(path,'PUT',data,{'Content-Type':'application/octet-stream'},expected=201)
 return dg

def push(tag):
 buf=io.BytesIO()
 with tarfile.open(fileobj=buf,mode='w') as tar:
  payload=f'registry upgrade fixture {tag}\n'.encode();info=tarfile.TarInfo('fixture.txt');info.size=len(payload);tar.addfile(info,io.BytesIO(payload))
 raw=buf.getvalue();layer=gzip.compress(raw,mtime=0)
 conf=json.dumps({'architecture':'amd64','os':'linux','rootfs':{'type':'layers','diff_ids':[digest(raw)]},'config':{}}).encode()
 ld=push_blob(layer);cd=push_blob(conf)
 manifest=json.dumps({'schemaVersion':2,'mediaType':'application/vnd.oci.image.manifest.v1+json','config':{'mediaType':'application/vnd.oci.image.config.v1+json','digest':cd,'size':len(conf)},'layers':[{'mediaType':'application/vnd.oci.image.layer.v1.tar+gzip','digest':ld,'size':len(layer)}]}).encode()
 request('/v2/smoke/manifests/'+tag,'PUT',manifest,{'Content-Type':'application/vnd.oci.image.manifest.v1+json'},expected=201)
 return manifest,{ld:layer,cd:conf}

def verify(tag,fixture):
 manifest,blobs=fixture
 _,actual=request('/v2/smoke/manifests/'+tag,headers={'Accept':'application/vnd.oci.image.manifest.v1+json'})
 assert actual==manifest
 for dg,data in blobs.items():
  _,actual=request('/v2/smoke/blobs/'+dg);assert actual==data
 print('PASS manifest and every blob retrieved byte-for-byte:',tag,flush=True)
if BACKEND=='s3':
 subprocess.run(['docker','network','create','registry-smoke'],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['docker','run','-d','--name','minio-smoke','--network','registry-smoke','-p','127.0.0.1:9000:9000','-e','MINIO_ROOT_USER=smokeuser','-e','MINIO_ROOT_PASSWORD=smokepassword','minio/minio:RELEASE.2025-09-07T16-13-09Z','server','/data'],check=True,stdout=subprocess.DEVNULL)
 for i in range(60):
  r=subprocess.run(['curl','--fail','--silent','http://127.0.0.1:9000/minio/health/live'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  if r.returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('MinIO did not become ready')
 subprocess.run(['curl','--fail','--silent','--show-error','--aws-sigv4','aws:amz:us-east-1:s3','--user','smokeuser:smokepassword','-X','PUT','http://127.0.0.1:9000/docker-registry'],check=True)
try:
 start('2.7.1');old=push('before-upgrade');verify('before-upgrade',old);stop()
 start('3.1.2');verify('before-upgrade',old);new=push('after-upgrade');verify('after-upgrade',new)
 request('/v2/smoke/manifests/'+digest(new[0]),'DELETE',expected=202)
 request('/v2/smoke/manifests/after-upgrade',headers={'Accept':'application/vnd.oci.image.manifest.v1+json'},expected=404)
 print('PASS Registry 3.1.2 manifest deletion',flush=True)
 stop();start('3.1.2');verify('before-upgrade',old)
 print(f'PASS all remote registry {BACKEND} smoke checks including 2.7.1-to-3.1.2 upgrade and restart persistence',flush=True)
finally:
 subprocess.run(['docker','logs','registry-smoke'],check=False)
 subprocess.run(['docker','rm','-f','registry-smoke'],check=False,stdout=subprocess.DEVNULL)

 if BACKEND=='s3':
  subprocess.run(['docker','rm','-f','minio-smoke'],check=False,stdout=subprocess.DEVNULL)
  subprocess.run(['docker','network','rm','registry-smoke'],check=False,stdout=subprocess.DEVNULL)
