#!/bin/bash

set -ex

createrepo_c /packages/archives
repo2module --module-name=kurl.local --module-stream=stable /packages/archives /tmp/modules.yaml
modifyrepo_c --mdtype=modules /tmp/modules.yaml /packages/archives/repodata
