SHELL := /bin/bash
PROJECT_NAME ?= kurl

.PHONY: deps
deps:
	yarn --silent --frozen-lockfile

.PHONY: test
test: deps
	yarn run --cwd=web test
	# missing api-tests, pact tests

.PHONY: prebuild
prebuild:
	rm -rf build
	mkdir -p build

.PHONY: lint
lint:
	npx tslint --project ./tsconfig.json --fix

.PHONY: build
build: prebuild
	`yarn bin`/tsc --project .
	mkdir -p bin
	cp newrelic.js bin/newrelic.js
	cp build/kurl.js bin/kurl
	chmod +x bin/kurl

.PHONY: run
run:
	bin/kurl serve

.PHONY: run-debug
run-debug:
	node --inspect=0.0.0.0:9229 bin/kurl serve

.PHONY: archive-modules
archive-modules:
	tar cfz node_modules.tar.gz node_modules/

.PHONY: build-cache
build-cache:
	@-docker pull repldev/${PROJECT_NAME}:latest > /dev/null 2>&1 ||:
	docker build -f Dockerfile.skaffoldcache -t repldev/${PROJECT_NAME}:latest .

.PHONY: publish-cache
publish-cache:
	docker push repldev/${PROJECT_NAME}:latest

.PHONY: build-staging
build-staging: REGISTRY = 923411875752.dkr.ecr.us-east-1.amazonaws.com
build-staging: build_and_push

.PHONY: build-production
build-production: REGISTRY = 799720048698.dkr.ecr.us-east-1.amazonaws.com
build-production: build_and_push

build_and_push:
	docker build -f deploy/Dockerfile-slim -t ${PROJECT_NAME}:$${CIRCLE_SHA1:0:7} .
	docker tag ${PROJECT_NAME}:$${CIRCLE_SHA1:0:7} $(REGISTRY)/${PROJECT_NAME}:$${CIRCLE_SHA1:0:7}
	docker push $(REGISTRY)/${PROJECT_NAME}:$${CIRCLE_SHA1:0:7}
