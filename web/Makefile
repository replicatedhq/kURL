SHELL := /bin/bash
PROJECT_NAME ?= kurl

.PHONY: deps
deps:
	yarn global add node-gyp
	yarn --silent --frozen-lockfile

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
	docker build -f deploy/Dockerfile-slim -t ${PROJECT_NAME}:$${BUILDKITE_COMMIT:0:7} .
	docker tag ${PROJECT_NAME}:$${BUILDKITE_COMMIT:0:7} $(REGISTRY)/${PROJECT_NAME}:$${BUILDKITE_COMMIT:0:7}
	docker push $(REGISTRY)/${PROJECT_NAME}:$${BUILDKITE_COMMIT:0:7}

.PHONY: can-i-deploy
can-i-deploy:
	pact-broker can-i-deploy --pacticipant kurl --broker-base-url https://replicated-pact-broker.herokuapp.com --latest

.PHONY: test-and-publish
test-and-publish: export PUBLISH_PACT_VERIFICATION = true
test-and-publish: export MYSQL_HOST = mysql
test-and-publish: export MYSQL_USER = replicated
test-and-publish: export MYSQL_DATABASE = replicated
test-and-publish: export MYSQL_PASSWORD = password
test-and-publish: export JWT_SIGNING_KEY = testsession
test-and-publish: export MOCK_ENTITLEMENTS = 1
test-and-publish: export IGNORE_RATE_LIMITS = 1
test-and-publish: export REPLICATED_ENVIRONMENT = dev
test-and-publish:
	yarn run test:provider:broker

.PHONY: test
test: export PACT_BROKER_USERNAME = replicated
test: export PACT_BROKER_PASSWORD = EnterpriseReady
test: export MYSQL_HOST = localhost
test: export MYSQL_PORT = 13306
test: export MYSQL_USER = replicated
test: export MYSQL_DATABASE = replicated
test: export MYSQL_PASSWORD = password
test: export JWT_SIGNING_KEY = testsession
test: export MOCK_ENTITLEMENTS = 1
test: export IGNORE_RATE_LIMITS = 1
test: export REPLICATED_ENVIRONMENT = dev
test: deps
	@-docker stop replicated-fixtures > /dev/null 2>&1 || :
	@-docker rm -f replicated-fixtures > /dev/null 2>&1 || :
	docker run --rm -d --name replicated-fixtures -p 13306:3306 repldev/replicated-fixtures:local
	while ! docker exec -it replicated-fixtures mysqladmin ping -hlocalhost --silent; do sleep 1; done
	yarn run test:provider:local
	@-sleep 1
	docker stop replicated-fixtures
	@-docker rm -f replicated-fixtures > /dev/null 2>&1 || :

.PHONY: publish-production
publish-production: OVERLAY = production
publish-production: REGISTRY = 799720048698.dkr.ecr.us-east-1.amazonaws.com
publish-production: GITOPS_OWNER = replicatedcom
publish-production: GITOPS_REPO = gitops-deploy
publish-production: GITOPS_BRANCH = release
publish-production: build_and_publish

.PHONY: publish-staging
publish-staging: OVERLAY = staging
publish-staging: REGISTRY = 923411875752.dkr.ecr.us-east-1.amazonaws.com
publish-staging: GITOPS_OWNER = replicatedcom
publish-staging: GITOPS_REPO = gitops-deploy
publish-staging: GITOPS_BRANCH = master
publish-staging: build_and_publish

build_and_publish:
	cd kustomize/overlays/$(OVERLAY); kustomize edit set image $(REGISTRY)/${PROJECT_NAME}=$(REGISTRY)/${PROJECT_NAME}:$${BUILDKITE_COMMIT:0:7}

	rm -rf deploy/$(OVERLAY)/work
	mkdir -p deploy/$(OVERLAY)/work; cd deploy/$(OVERLAY)/work; git clone --single-branch -b $(GITOPS_BRANCH) git@github.com:$(GITOPS_OWNER)/$(GITOPS_REPO)
	mkdir -p deploy/$(OVERLAY)/work/$(GITOPS_REPO)/${PROJECT_NAME}

	kustomize build kustomize/overlays/$(OVERLAY) > deploy/$(OVERLAY)/work/$(GITOPS_REPO)/${PROJECT_NAME}/${PROJECT_NAME}.yaml

	cd deploy/$(OVERLAY)/work/$(GITOPS_REPO)/${PROJECT_NAME}; \
	  git add . ;\
	  git commit --allow-empty -m "$${BUILDKITE_BUILD_URL}"; \
          git push origin $(GITOPS_BRANCH)
