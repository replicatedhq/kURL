#!/bin/bash

set -eo pipefail

function require() {
    if [ -z "$2" ]; then
        echo "validation failed: $1 unset"
        exit 1
    fi
}

require GH_PAT "${GH_PAT}"

for package in $(bin/list-all-packages.sh)
do
	curl -H "Authorization: token $GH_PAT" \
		-H 'Accept: application/json' \
		-d "{\"event_type\": \"build-package-prod\", \"client_payload\": {\"package\": \"${package}\"}}"
		"https://api.github.com/repos/replicatedhq/kurl/dispatches"

	curl -H "Authorization: token $GH_PAT" \
		-H 'Accept: application/json' \
		-d "{\"event_type\": \"build-package-staging\", \"client_payload\": {\"package\": \"${package}\"}}"
		"https://api.github.com/repos/replicatedhq/kurl/dispatches"
done
