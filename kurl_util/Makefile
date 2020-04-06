SHELL := /bin/bash
KURL_UTIL_IMAGE ?= replicated/kurl-util:alpha

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

.PHONY: clean
clean:
	rm -rf ./bin

.PHONY: deps
deps:
	go get golang.org/x/lint/golint

.PHONY: lint
lint:
	golint -set_exit_status ./...

.PHONY: vet
vet:
	go vet ./...

.PHONY: test
test: lint vet
	go test ./cmd/...

.PHONY: build
build: bin/yamlutil bin/subnet bin/docker-config

bin/yamlutil:
	go build -o bin/yamlutil cmd/yamlutil/main.go

bin/subnet:
	go build -o bin/subnet cmd/subnet/main.go

bin/docker-config:
	go build -o bin/docker-config cmd/docker/main.go

.PHONY: kurl-util-image
kurl-util-image:
	docker build -t $(KURL_UTIL_IMAGE) -f deploy/Dockerfile --build-arg commit="${GIT_SHA}" .

.PHONY: build-and-push-kurl-util-image
build-and-push-kurl-util-image: kurl-util-image
	docker push $(KURL_UTIL_IMAGE)
