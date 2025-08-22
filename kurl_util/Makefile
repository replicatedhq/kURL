SHELL := /bin/bash
KURL_UTIL_IMAGE ?= replicated/kurl-util:alpha
VERSION_PACKAGE = github.com/replicatedhq/kurl/pkg/version
VERSION_TAG ?= 0.0.1
DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"`
CURRENT_USER := $(shell id -u -n)

export GO111MODULE=on

GIT_TREE = $(shell git rev-parse --is-inside-work-tree 2>/dev/null)
ifneq "$(GIT_TREE)" ""
define GIT_UPDATE_INDEX_CMD
git update-index --assume-unchanged
endef
define GIT_SHA
`git rev-parse HEAD`
endef
else
define GIT_UPDATE_INDEX_CMD
echo "Not a git repo, skipping git update-index"
endef
define GIT_SHA
""
endef
endif

define LDFLAGS
-ldflags "\
	-X ${VERSION_PACKAGE}.version=${VERSION_TAG} \
	-X ${VERSION_PACKAGE}.gitSHA=${GIT_SHA} \
	-X ${VERSION_PACKAGE}.buildTime=${DATE} \
"
endef

.PHONY: clean
clean:
	rm -rf ./bin

.PHONY: test
test:
	go test ./cmd/...

.PHONY: build
build: bin/yamlutil bin/subnet bin/docker-config bin/config bin/installermerge bin/yamltobash bin/bashmerge bin/bcrypt bin/htpasswd bin/network bin/toml bin/veleroplugin bin/vendorflights bin/pvmigrate

bin/yamlutil: cmd/yamlutil/main.go
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/yamlutil cmd/yamlutil/main.go

bin/subnet:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/subnet cmd/subnet/main.go

bin/docker-config:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/docker-config cmd/docker/main.go

bin/config:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/config cmd/config/main.go

bin/installermerge:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/installermerge cmd/installermerge/main.go

bin/yamltobash:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/yamltobash cmd/yamltobash/main.go

bin/bashmerge:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/bashmerge cmd/bashmerge/main.go

bin/bcrypt:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/bcrypt cmd/bcrypt/main.go

bin/htpasswd:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/htpasswd cmd/htpasswd/main.go

bin/network:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/network cmd/network/main.go

bin/toml:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/toml cmd/toml/main.go

bin/veleroplugin: cmd/veleroplugin/main.go
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/veleroplugin cmd/veleroplugin/main.go

bin/vendorflights:
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/vendorflights cmd/vendorflights/main.go

bin/pvmigrate: cmd/pvmigrate/main.go
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/pvmigrate cmd/pvmigrate/main.go

GH_AVAILABLE ?= $(shell which gh >/dev/null 2>&1 && echo 1 || echo 0)

.PHONY: kurl-util-image
# Check if gh is available and set CRITOOLS_VERSION accordingly
ifeq ($(GH_AVAILABLE),1)
kurl-util-image: CRITOOLS_VERSION := $(shell gh api repos/kubernetes-sigs/cri-tools/releases/latest --jq .tag_name)
else
kurl-util-image: CRITOOLS_VERSION := $(shell curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
endif
kurl-util-image:
	docker build -t $(KURL_UTIL_IMAGE) -f deploy/Dockerfile \
		--build-arg COMMIT="${GIT_SHA}" \
		--build-arg CRITOOLS_VERSION="${CRITOOLS_VERSION}" \
		../

.PHONY: push-kurl-util-image
push-kurl-util-image:
	docker push $(KURL_UTIL_IMAGE)

.PHONY: build-and-push-kurl-util-image
build-and-push-kurl-util-image: kurl-util-image push-kurl-util-image

.PHONY: build-ttl.sh
build-ttl.sh:
	docker build --pull -f deploy/Dockerfile -t ttl.sh/$(CURRENT_USER)/kurl_util:12h ../
	docker push ttl.sh/${CURRENT_USER}/kurl_util:12h
