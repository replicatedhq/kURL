SHELL := /bin/bash

IMAGE := kurlsh/rook-ceph:v1.0.4

DATE := $(shell date '+%Y%m%d')

GIT_TREE = $(shell git rev-parse --is-inside-work-tree 2>/dev/null)
ifneq "$(GIT_TREE)" ""
define GIT_UPDATE_INDEX_CMD
git update-index --assume-unchanged
endef
define GIT_SHA
`git rev-parse --short HEAD`
endef
else
define GIT_UPDATE_INDEX_CMD
echo "Not a git repo, skipping git update-index"
endef
define GIT_SHA
""
endef
endif

.PHONY: all
all: build scan push

.PHONY: build
build:
	docker build --no-cache --pull -t $(IMAGE)-$(GIT_SHA)-$(DATE) -f Dockerfile .

.PHONY: scan
scan:
	trivy image \
		--exit-code=1 \
		--severity="MEDIUM,HIGH,CRITICAL" \
		--ignore-unfixed \
		--ignore-policy=.trivyignore.rego \
		$(IMAGE)-$(GIT_SHA)-$(DATE)

.PHONY: push
push:
	docker push $(IMAGE)-$(GIT_SHA)-$(DATE)

.PHONY: deps
deps:
	curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.27.1
