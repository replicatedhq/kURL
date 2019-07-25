## Build a new Docker bundle for Ubuntu 16.04

First use CircleCI's API to trigger a new build and push
```
curl -u ${CIRCLE_CI_TOKEN}: \
     -d build_parameters[CIRCLE_JOB]=build_ubuntu_docker_package \
     https://circleci.com/api/v1.1/project/github/replicatedhq/replicated-installer/tree/master \
```

Then update chatops deployer with the new image tag. No code changes are required in this repo.

## Build a new Docker bundle for RHEL 7

```
curl -u ${CIRCLE_CI_TOKEN}: \
     -d build_parameters[CIRCLE_JOB]=build_rhel_docker_package \
     https://circleci.com/api/v1.1/project/github/replicatedhq/replicated-installer/tree/master
```

Then update chatops deployer with the new image tag. No code changes are required in this repo.

## Build new K8s package for Ubuntu 16.04

```
curl -u ${CIRCLE_CI_TOKEN}: \
     -d build_parameters[CIRCLE_JOB]=build_ubuntu_k8s_packages \
     -d build_parameters[K8S_VERSION]=v1.15.0 \
     https://circleci.com/api/v1.1/project/github/replicatedhq/replicated-installer/tree/master
```

Update chatops deployer with the new image tags.
Update the Ubuntu image tags [in this repo](TODO)

## Build new K8s package for RHEL 7

```
curl -u ${CIRCLE_CI_TOKEN}: \
     -d build_parameters[CIRCLE_JOB]=build_rhel_k8s_packages \
     -d build_parameters[K8S_VERSION]=v1.15.0 \
     https://circleci.com/api/v1.1/project/github/replicatedhq/replicated-installer/tree/master
```

Update chatops deployer with the new image tags.
Update the RHEL image tags [in this repo](TODO)

## Build new K8s container image bundles for all supported versions of K8s

This will package up images such as `kube-apiserver` used on every OS for airgap installs.
This should only be needed when adding a new supported version of K8s.

```
curl -u ${CIRCLE_CI_TOKEN}: \
     -d build_parameters[CIRCLE_JOB]=build_k8s_bundles \
     -d build_parameters[K8S_VERSION]=v1.15.0 \
     https://circleci.com/api/v1.1/project/github/replicatedhq/replicated-installer/tree/master
```

Update chatops deployer with the new image tags.
Each image in the created bundle will need to be [retagged with its full name](TODO)
