SHELL := /bin/bash

IMAGE := kurlsh/weave-kube:2.6.5

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
	docker build --no-cache --pull -t $(IMAGE)-$(DATE)-$(GIT_SHA) -f Dockerfile .

.PHONY: scan
scan:
	grype $(IMAGE)-$(DATE)-$(GIT_SHA) \
		--fail-on high \
		--only-fixed

.PHONY: push
push:
	docker push $(IMAGE)-$(DATE)-$(GIT_SHA)

.PHONY: deps
deps:
	curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
