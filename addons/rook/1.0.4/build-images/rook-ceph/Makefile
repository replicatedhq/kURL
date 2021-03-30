SHELL := /bin/bash

IMAGE := kurlsh/rook-ceph:v1.0.4
WHITELIST := "(GHSA\-|perl\-Pod\-Escapes)"

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
	../../../../../bin/image-scan.sh $(IMAGE)-$(GIT_SHA)-$(DATE) $(WHITELIST)

.PHONY: push
push:
	docker push $(IMAGE)-$(GIT_SHA)-$(DATE)
