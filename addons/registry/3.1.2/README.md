
[Docker registry](https://github.com/docker/distribution) is an OCI compatible image registry.
This addon deploys it to the `kurl` namespace.

## TLS

TLS is enabled on the registry using a certificate signed by the Kubernetes cluster CA.
The kubeadm bootstrapping process distributes the CA to every node in the cluster at filepath /etc/kubernetes/pki/ca.crt.
The registry addon script copies that file to /etc/docker/certs.d/<service-IP>/ca.crt, telling Docker to trust the registry certificate signed by that CA.
The service IP is from the Service of type ClusterIP that is created along with the Deployment.

## Auth

All access to the registry requires authentication with [basic auth](https://docs.docker.com/registry/deploying/#native-basic-auth).
A new user/password is generated and placed in a secret in the default namespace to be used as an imagePullSecret by Pods.
The user has push/pull access to all repos in the registry.

## Options

By default it is not possible to push to the registry from remote hosts.
Use the `registry-publish-port=<port>` flag to configure the registry to listen on a NodePort.
