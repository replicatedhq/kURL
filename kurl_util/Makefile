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
build: bin/yamlutil bin/subnet bin/docker-config bin/config bin/installermerge bin/yamltobash bin/bashmerge bin/bcrypt bin/htpasswd bin/network bin/toml bin/veleroplugin bin/vendorflights bin/pvmigrate bin/rook-pv-migrator

bin/yamlutil: cmd/yamlutil/main.go
	go build ${LDFLAGS} -o bin/yamlutil cmd/yamlutil/main.go

bin/subnet:
	go build ${LDFLAGS} -o bin/subnet cmd/subnet/main.go

bin/docker-config:
	go build ${LDFLAGS} -o bin/docker-config cmd/docker/main.go

bin/config:
	go build ${LDFLAGS} -o bin/config cmd/config/main.go

bin/installermerge:
	go build ${LDFLAGS} -o bin/installermerge cmd/installermerge/main.go

bin/yamltobash:
	go build ${LDFLAGS} -o bin/yamltobash cmd/yamltobash/main.go

bin/bashmerge:
	go build ${LDFLAGS} -o bin/bashmerge cmd/bashmerge/main.go

bin/bcrypt:
	go build ${LDFLAGS} -o bin/bcrypt cmd/bcrypt/main.go

bin/htpasswd:
	go build ${LDFLAGS} -o bin/htpasswd cmd/htpasswd/main.go

bin/network:
	go build ${LDFLAGS} -o bin/network cmd/network/main.go

bin/toml:
	go build ${LDFLAGS} -o bin/toml cmd/toml/main.go

bin/veleroplugin: cmd/veleroplugin/main.go
	CGO_ENABLED=0 go build ${LDFLAGS} -o bin/veleroplugin cmd/veleroplugin/main.go

bin/vendorflights:
	go build ${LDFLAGS} -o bin/vendorflights cmd/vendorflights/main.go

bin/pvmigrate: cmd/pvmigrate/main.go
	go build ${LDFLAGS} -o bin/pvmigrate cmd/pvmigrate/main.go

bin/rook-pv-migrator:
	rm -rf .tmp/persistent-volume-migrator
	mkdir -p .tmp/persistent-volume-migrator
	cd .tmp/persistent-volume-migrator \
		&& git clone https://github.com/ceph/persistent-volume-migrator.git . \
		&& go build -o ../../bin/rook-pv-migrator
	chmod +x ./bin/rook-pv-migrator
	rm -rf .tmp/persistent-volume-migrator

.PHONY: kurl-util-image
kurl-util-image:
	docker build -t $(KURL_UTIL_IMAGE) -f deploy/Dockerfile --build-arg commit="${GIT_SHA}" ../

.PHONY: push-kurl-util-image
push-kurl-util-image:
	docker push $(KURL_UTIL_IMAGE)

.PHONY: build-and-push-kurl-util-image
build-and-push-kurl-util-image: kurl-util-image push-kurl-util-image

.PHONY: build-ttl.sh
build-ttl.sh:
	docker build --pull -f deploy/Dockerfile -t ttl.sh/$(CURRENT_USER)/kurl_util:12h ../
	docker push ttl.sh/${CURRENT_USER}/kurl_util:12h
