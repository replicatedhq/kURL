# Remove the use of docker Dommands in the kURL.sh install script
 
This proposal outlines the benefits and challenges of removing the use of Docker commands in the kURL.sh install script to facilitate the use of containerd and other future container runtimes.

## Goals

- Remove use of Docker commands in kURL install script
- Provide a pathway for use using containerd runtime

## Non Goals

- Remove use of Docker commands in kURL build process. This can be kept without issue
- Remove use of Docker commands in tasks.sh. These are not part of the normal install process.

## Background

As of Docker 18.09, Docker has been split into separate packages for the runtime and client. 
The kURL install script currently uses the client to execute several setup tasks during the install.
Certain end users of kURL have requested the ability to use containerd as a runtime, and the use of docker client commands in the install prevents this.
Additionally, this will be needed for CentOS 8 installs of Docker, as they do not have docker packages.

## High-Level Design

There are a few categories of ways in which Docker is used in the kURL installer.

- To utilize binaries from the kurl_util image to change config
- To generate bcrypt hashes
- To load images

## Detailed Design

Places to move functionality from kurl_util to go binaries:

https://github.com/replicatedhq/kURL/blob/master/scripts/install.sh#L88
https://github.com/replicatedhq/kURL/blob/master/scripts/join.sh#L60
https://github.com/replicatedhq/kURL/blob/master/scripts/common/kubernetes.sh#L340
https://github.com/replicatedhq/kURL/blob/master/scripts/common/kubernetes.sh#L360
https://github.com/replicatedhq/kURL/blob/master/scripts/common/kubernetes.sh#L366
https://github.com/replicatedhq/kURL/blob/master/scripts/common/kubernetes.sh#L401
https://github.com/replicatedhq/kURL/blob/master/scripts/common/kubernetes.sh#L424
https://github.com/replicatedhq/kURL/blob/master/scripts/common/kubernetes.sh#L430
https://github.com/replicatedhq/kURL/blob/master/scripts/common/upgrade.sh#L154
https://github.com/replicatedhq/kURL/blob/master/scripts/common/common.sh#L261

Places to use a bcrypt binary instead of an image:

https://github.com/replicatedhq/kURL/blob/master/addons/registry/2.7.1/install.sh#L65
https://github.com/replicatedhq/kURL/blob/master/scripts/common/tasks.sh#L204
https://github.com/replicatedhq/kURL/blob/master/addons/kotsadm/1.15.2/install.sh#L134

Places to handle loading of images:

https://github.com/replicatedhq/kURL/blob/master/scripts/common/common.sh#L206

## Security Considerations

Currently we use the epicsoft/bcrypt:latest image to generate bcrypt passwords.
If we move this functionality to a go binary we must be cautious about usage. 
