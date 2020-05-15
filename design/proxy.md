# Proxies

The installer should work behind a proxy.

## Goals

- Proxy installs complete successfully.
- Docker can pull images from remote and local registries.

## Non Goals

- Automatically detect proxy from environment.
- Validate kotsadm add-on works with a proxy.
- Support docker versions below 19.03.

## Background

The kURL spec has a field for an http proxy address, but the feature has not been implemented.

## High-Level Design

Use the proxy when downloading packages from S3.
Configure docker to pull from remote registries with the proxy and the local registry without the proxy.
Add `PROXY_ADDRESS` and `NO_PROXY` environment variables to the kotsadm add-on.

## Detailed Design

### Spec

Proxy configuration uses three fields under the kurl section of the installer spec:

```yaml
apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: proxy
spec:
  kurl:
    proxyAddress: http://10.128.0.3:3128
    additionalNoProxyAddresses:
    - 10.128.0.4
    - 10.128.0.5
    - 10.128.0.6
    - registry.internal
    noProxy: false
```

If `noProxy` is set to `true` then the other proxy fields in the spec are ignored and the installer does not attempt to do any proxy configuration.
This field already exists on the kurl spec.

The `proxyAddress` field is the URL of a proxy.
This field already exists on the kurl spec.
The installer will validate the proxy URL at runtime by making a proxied request to `https://api.replicated.com/market/v1/echo/ip` and will bail if the request fails.

The `additionalNoProxyAddresses` field is new.
This field is ignored if `proxyAddress` is unset.
It accepts a list of IPs and hostnames.
Cluster administrators should add all node IPs to this field.
IP addresses may be in CIDR notation.
The default set of no proxy addresses is the private IP of the current machine, the pod CIDR, and the service CIDR.
Any other addresses specified in this field will be added to the default set to construct the NO_PROXY environment variable.

### Docker add-on

If docker is enabled the installer will create the file /etc/systemd/system/docker.service.d/http-proxy.conf.
The environment variables `HTTP_PROXY` and `NO_PROXY` will be set in this file.
On subsequent runs the installer will check if any changes are required in this file and restart docker only if needed.
If `docker.preserveConfig` is set to true in the spec then this file will never be created or modified and docker will not be restarted.

The join.sh and upgrade.sh scripts will apply the same configuration to remote workers or masters.
After making a change to proxy configuration in the spec, cluster adminstrators can re-run the upgrade.sh script on remote nodes to reconfigure docker.

### Kotsadm add-on

If a proxy is configured then the installer will add the environment variables `PROXY_ADDRESS` and `NO_PROXY` to the kotsadm deployment.
`PROXY_ADDRESS` is used because setting `HTTP_PROXY` breaks the kotsadm add-on.

## Alternatives Considered

### Prompt for a proxy if none is specified.

This would make automation harder.

### Automatically detect HTTP_PROXY and NO_PROXY in the environment

This would create multiple sources of truth and non-deterministic results.

### Support older versions of Docker.

Docker 18.09 does not support CIDR notation in the NO_PROXY env var.
It's possible to add support for 18.09 by adding the registry cluster IP to docker's configuration.

## Security Considerations

None
