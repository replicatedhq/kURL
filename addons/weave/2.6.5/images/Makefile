SHELL := /bin/bash

IMAGE_TAG := 2.6.5

WEAVE_KUBE_IMAGE := kurlsh/weave-kube
WEAVE_NPC_IMAGE := kurlsh/weave-npc
WEAVEEXEC_IMAGE := kurlsh/weaveexec

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

# weave-kube

.PHONY: weave-kube
weave-kube: weave-kube-build weave-kube-scan weave-kube-push

.PHONY: weave-kube-build
weave-kube-build:
	docker build --no-cache --pull -t $(WEAVE_KUBE_IMAGE):$(IMAGE_TAG)-$(GIT_SHA) -f weave-kube/Dockerfile .

.PHONY: weave-kube-scan
weave-kube-scan:
	@echo "scan not implemented"

.PHONY: weave-kube-push
weave-kube-push:
	docker push $(WEAVE_KUBE_IMAGE):$(IMAGE_TAG)-$(GIT_SHA)

# weave-npc

.PHONY: weave-npc
weave-npc: weave-npc-build weave-npc-scan weave-npc-push

.PHONY: weave-npc-build
weave-npc-build:
	docker build --no-cache --pull -t $(WEAVE_NPC_IMAGE):$(IMAGE_TAG)-$(GIT_SHA) -f weave-npc/Dockerfile .

.PHONY: weave-npc-scan
weave-npc-scan:
	@echo "scan not implemented"

.PHONY: weave-npc-push
weave-npc-push:
	docker push $(WEAVE_NPC_IMAGE):$(IMAGE_TAG)-$(GIT_SHA)

# weaveexec

.PHONY: weaveexec
weaveexec: weaveexec-build weaveexec-scan weaveexec-push

.PHONY: weaveexec-build
weaveexec-build:
	docker build --no-cache --pull -t $(WEAVEEXEC_IMAGE):$(IMAGE_TAG)-$(GIT_SHA) -f weaveexec/Dockerfile .

.PHONY: weaveexec-scan
weaveexec-scan:
	@echo "scan not implemented"

.PHONY: weaveexec-push
weaveexec-push:
	docker push $(WEAVEEXEC_IMAGE):$(IMAGE_TAG)-$(GIT_SHA)
