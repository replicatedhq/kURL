SHELL := /bin/bash

.PHONY: build
build:
	docker run --rm -v `pwd`:`pwd` --workdir `pwd`/build quay.io/coreos/jsonnet-ci ./build.sh
