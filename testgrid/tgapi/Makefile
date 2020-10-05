SHELL := /bin/bash

export GO111MODULE=on

.PHONY: modules
modules:
	go mod download

.PHONY: test
test:
	go test -v ./...

.PHONY: build
build: fmt vet build-api 

.PHONY: build-api
build-api:
	mkdir -p bin
	go build \
		-o ./bin/tgapi \
		./cmd/api

.PHONY: fmt
fmt:
	go fmt ./...

.PHONY: vet
vet:
	go vet ./...

.PHONY: run
run:
	./bin/tgapi run
