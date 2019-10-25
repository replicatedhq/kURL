Run `make up` for developing with skaffold.


The proxy will not serve until a secret named kotsadm-tls exists.
Create a self-signed cert/key pair in the `kotsadm-tls` secret:

```
source addons/kotsadm/0.9.12/install.sh
PRIVATE_ADDRESS=<private ip> kotsadm_tls_secret
```

That secret will have the flag `acceptAnonymousUploads` which allows anybody to upload a new cert at /tls.
After the first upload that flag will be turned off and the cert/key in the kotsadm-secret will be replaced with the uploaded pair.
