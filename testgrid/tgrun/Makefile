SHELL := /bin/bash

export GO111MODULE=on

.PHONY: modules
modules:
	go mod download

.PHONY: test
test:
	go test -v ./...

.PHONY: build
build: fmt vet build-cli

.PHONY: build-cli
build-cli:
	mkdir -p bin
	go build \
		-i \
		-o ./bin/tgrun \
		./cmd/run

.PHONY: fmt
fmt:
	go fmt ./...

.PHONY: vet
vet:
	go vet ./...

