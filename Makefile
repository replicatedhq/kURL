SHELL := /bin/bash
KURL_UTIL_IMAGE := replicated/kurl-util:latest

.PHONY: clean
clean:
	rm -rf build tmp dist

dist/common.tar.gz: build/kustomize build/shared build/krew
	mkdir -p dist
	tar cf dist/common.tar -C build kustomize
	tar rf dist/common.tar -C build shared
	tar rf dist/common.tar -C build krew
	gzip dist/common.tar

dist/aws-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh addons/aws/$*/Manifest build/addons/aws/$*
	tar cf - -C build addons/aws/$* | gzip > dist/aws-$*.tar.gz

dist/nodeless-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh addons/nodeless/$*/Manifest build/addons/nodeless/$*
	tar cf - -C build addons/nodeless/$* | gzip > dist/nodeless-$*.tar.gz

dist/calico-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh addons/calico/$*/Manifest build/addons/calico/$*
	tar cf - -C build addons/calico/$* | gzip > dist/calico-$*.tar.gz

dist/weave-%.tar.gz: build/addons
	mkdir -p build/addons/weave/$*/images
	bin/save-manifest-assets.sh addons/weave/$*/Manifest build/addons/weave/$*
	mkdir -p dist
	tar cf - -C build addons/weave/$* | gzip > dist/weave-$*.tar.gz

dist/rook-%.tar.gz: build/addons
	mkdir -p build/addons/rook/$*/images
	bin/save-manifest-assets.sh addons/rook/$*/Manifest build/addons/rook/$*
	mkdir -p dist
	tar cf - -C build addons/rook/$* | gzip > dist/rook-$*.tar.gz

dist/contour-%.tar.gz: build/addons
	mkdir -p build/addons/contour/$*/images
	bin/save-manifest-assets.sh addons/contour/$*/Manifest build/addons/contour/$*
	mkdir -p dist
	tar cf - -C build addons/contour/$* | gzip > dist/contour-$*.tar.gz

dist/registry-%.tar.gz: build/addons
	mkdir -p build/addons/registry/$*/images
	bin/save-manifest-assets.sh addons/registry/$*/Manifest build/addons/registry/$*
	mkdir -p dist
	tar cf - -C build addons/registry/$* | gzip > dist/registry-$*.tar.gz

dist/prometheus-%.tar.gz: build/addons
	mkdir -p build/addons/prometheus/$*/images
	bin/save-manifest-assets.sh addons/prometheus/$*/Manifest build/addons/prometheus/$*
	mkdir -p dist
	tar cf - -C build addons/prometheus/$* | gzip > dist/prometheus-$*.tar.gz

dist/kotsadm-%.tar.gz: build/addons
	mkdir -p build/addons/kotsadm/$*/images
	bin/save-manifest-assets.sh addons/kotsadm/$*/Manifest build/addons/kotsadm/$*
	mkdir -p dist
	tar cf - -C build addons/kotsadm/$* | gzip > dist/kotsadm-$*.tar.gz

dist/docker-%.tar.gz:
	${MAKE} build/packages/docker/$*/ubuntu-16.04
	${MAKE} build/packages/docker/$*/ubuntu-18.04
	${MAKE} build/packages/docker/$*/rhel-7
	mkdir -p dist
	tar cf - -C build packages/docker/$* | gzip > dist/docker-$*.tar.gz

dist/kubernetes-%.tar.gz:
	${MAKE} build/packages/kubernetes/$*/images
	${MAKE} build/packages/kubernetes/$*/ubuntu-16.04
	${MAKE} build/packages/kubernetes/$*/ubuntu-18.04
	${MAKE} build/packages/kubernetes/$*/rhel-7
	mkdir -p dist
	tar cf - -C build packages/kubernetes/$* | gzip > dist/kubernetes-$*.tar.gz

build/packages/kubernetes/%/images:
	mkdir -p build/packages/kubernetes/$*/images
	bin/save-manifest-assets.sh packages/kubernetes/$*/Manifest build/packages/kubernetes/$*

build/install.sh:
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/install.sh | sed '$$d' > tmp/install.sh
	for script in $(shell cat scripts/install.sh | grep '. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/install.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/install.sh | sed '1d' >> tmp/install.sh
	mv tmp/install.sh build/install.sh
	chmod +x build/install.sh

build/templates/install.tmpl: build/install.sh
	mkdir -p build/templates
	sed 's/^KUBERNETES_VERSION=.*/KUBERNETES_VERSION="{{= KUBERNETES_VERSION }}"/' "build/install.sh" | \
		sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^WEAVE_VERSION=.*/WEAVE_VERSION="{{= WEAVE_VERSION }}"/' | \
		sed 's/^ROOK_VERSION=.*/ROOK_VERSION="{{= ROOK_VERSION }}"/' | \
		sed 's/^CONTOUR_VERSION=.*/CONTOUR_VERSION="{{= CONTOUR_VERSION }}"/' | \
		sed 's/^REGISTRY_VERSION=.*/REGISTRY_VERSION="{{= REGISTRY_VERSION }}"/' | \
		sed 's/^PROMETHEUS_VERSION=.*/PROMETHEUS_VERSION="{{= PROMETHEUS_VERSION }}"/' | \
		sed 's/^KOTSADM_VERSION=.*/KOTSADM_VERSION="{{= KOTSADM_VERSION }}"/' | \
		sed 's/^KOTSADM_APPLICATION_SLUG=.*/KOTSADM_APPLICATION_SLUG="{{= KOTSADM_APPLICATION_SLUG }}"/' | \
		sed 's/^FLAGS=.*/FLAGS="{{= FLAGS }}"/' \
		> build/templates/install.tmpl

build/join.sh:
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/join.sh | sed '$$d' > tmp/join.sh
	for script in $(shell cat scripts/join.sh | grep '. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/join.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/join.sh | sed '1d' >> tmp/join.sh
	mv tmp/join.sh build/join.sh
	chmod +x build/join.sh

build/templates/join.tmpl: build/join.sh
	mkdir -p build/templates
	sed 's/^KUBERNETES_VERSION=.*/KUBERNETES_VERSION="{{= KUBERNETES_VERSION }}"/' "build/join.sh" | \
		sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^WEAVE_VERSION=.*/WEAVE_VERSION="{{= WEAVE_VERSION }}"/' | \
		sed 's/^ROOK_VERSION=.*/ROOK_VERSION="{{= ROOK_VERSION }}"/' | \
		sed 's/^CONTOUR_VERSION=.*/CONTOUR_VERSION="{{= CONTOUR_VERSION }}"/' | \
		sed 's/^REGISTRY_VERSION=.*/REGISTRY_VERSION="{{= REGISTRY_VERSION }}"/' | \
		sed 's/^PROMETHEUS_VERSION=.*/PROMETHEUS_VERSION="{{= PROMETHEUS_VERSION }}"/' | \
		sed 's/^KOTSADM_VERSION=.*/KOTSADM_VERSION="{{= KOTSADM_VERSION }}"/' | \
		sed 's/^KOTSADM_APPLICATION_SLUG=.*/KOTSADM_APPLICATION_SLUG="{{= KOTSADM_APPLICATION_SLUG }}"/' | \
		sed 's/^FLAGS=.*/FLAGS="{{= FLAGS }}"/' \
		> build/templates/join.tmpl

build/upgrade.sh:
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/upgrade.sh | sed '$$d' > tmp/upgrade.sh
	for script in $(shell cat scripts/upgrade.sh | grep '. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/upgrade.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/upgrade.sh | sed '1d' >> tmp/upgrade.sh
	mv tmp/upgrade.sh build/upgrade.sh
	chmod +x ./build/upgrade.sh
	
build/templates/upgrade.tmpl: build/upgrade.sh
	mkdir -p build/templates
	sed 's/^KUBERNETES_VERSION=.*/KUBERNETES_VERSION="{{= KUBERNETES_VERSION }}"/' "build/upgrade.sh" | \
		sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^WEAVE_VERSION=.*/WEAVE_VERSION="{{= WEAVE_VERSION }}"/' | \
		sed 's/^ROOK_VERSION=.*/ROOK_VERSION="{{= ROOK_VERSION }}"/' | \
		sed 's/^CONTOUR_VERSION=.*/CONTOUR_VERSION="{{= CONTOUR_VERSION }}"/' | \
		sed 's/^REGISTRY_VERSION=.*/REGISTRY_VERSION="{{= REGISTRY_VERSION }}"/' | \
		sed 's/^PROMETHEUS_VERSION=.*/PROMETHEUS_VERSION="{{= PROMETHEUS_VERSION }}"/' | \
		sed 's/^KOTSADM_VERSION=.*/KOTSADM_VERSION="{{= KOTSADM_VERSION }}"/' | \
		sed 's/^KOTSADM_APPLICATION_SLUG=.*/KOTSADM_APPLICATION_SLUG="{{= KOTSADM_APPLICATION_SLUG }}"/' | \
		sed 's/^FLAGS=.*/FLAGS="{{= FLAGS }}"/' \
		> build/templates/upgrade.tmpl

build/addons:
	mkdir -p build
	cp -r addons build/

build/krew:
	mkdir -p build/krew
	docker build -t krew -f bundles/krew/Dockerfile bundles/krew
	- docker rm -f krew 2>/dev/null
	docker create --name krew krew:latest
	docker cp krew:/krew build/
	docker rm krew

build/kustomize:
	mkdir -p build
	cp -r scripts/kustomize build/

build/shared: kurl-util-image
	mkdir -p build/shared
	docker save $(KURL_UTIL_IMAGE) > build/shared/kurl-util.tar

build/packages/docker/%/ubuntu-16.04:
	docker build \
		--build-arg DOCKER_VERSION=$* \
		-t kurl/ubuntu-1604-docker:$* \
		-f bundles/docker-ubuntu1604/Dockerfile \
		bundles/docker-ubuntu1604
	-docker rm -f docker-ubuntu1604-$* 2>/dev/null
	docker create --name docker-ubuntu1604-$* kurl/ubuntu-1604-docker:$*
	mkdir -p build/packages/docker/$*/ubuntu-16.04
	docker cp docker-ubuntu1604-$*:/packages/archives/. build/packages/docker/$*/ubuntu-16.04
	docker rm docker-ubuntu1604-$*

build/packages/docker/%/ubuntu-18.04:
	docker build \
		--build-arg DOCKER_VERSION=$* \
		-t kurl/ubuntu-1804-docker:$* \
		-f bundles/docker-ubuntu1804/Dockerfile \
		bundles/docker-ubuntu1804
	-docker rm -f docker-ubuntu1804-$* 2>/dev/null
	docker create --name docker-ubuntu1804-$* kurl/ubuntu-1804-docker:$*
	mkdir -p build/packages/docker/$*/ubuntu-18.04
	docker cp docker-ubuntu1804-$*:/packages/archives/. build/packages/docker/$*/ubuntu-18.04
	docker rm docker-ubuntu1804-$*

build/packages/docker/%/rhel-7:
	docker build \
		--build-arg DOCKER_VERSION=$* \
		-t kurl/rhel-7-docker:$* \
		-f bundles/docker-rhel7/Dockerfile \
		bundles/docker-rhel7
	-docker rm -f docker-rhel7 2>/dev/null
	docker create --name docker-rhel7-$* kurl/rhel-7-docker:$*
	mkdir -p build/packages/docker/$*/rhel-7
	docker cp docker-rhel7-$*:/packages/archives/. build/packages/docker/$*/rhel-7
	docker rm docker-rhel7-$*

build/packages/kubernetes/%/ubuntu-16.04:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		-t kurl/ubuntu-1604-k8s:$* \
		-f bundles/k8s-ubuntu1604/Dockerfile \
		bundles/k8s-ubuntu1604
	-docker rm -f k8s-ubuntu1604-$* 2>/dev/null
	docker create --name k8s-ubuntu1604-$* kurl/ubuntu-1604-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-16.04
	docker cp k8s-ubuntu1604-$*:/packages/archives/. build/packages/kubernetes/$*/ubuntu-16.04/
	docker rm k8s-ubuntu1604-$*

build/packages/kubernetes/%/ubuntu-18.04:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		-t kurl/ubuntu-1804-k8s:$* \
		-f bundles/k8s-ubuntu1804/Dockerfile \
		bundles/k8s-ubuntu1804
	-docker rm -f k8s-ubuntu1804-$* 2>/dev/null
	docker create --name k8s-ubuntu1804-$* kurl/ubuntu-1804-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-18.04
	docker cp k8s-ubuntu1804-$*:/packages/archives/. build/packages/kubernetes/$*/ubuntu-18.04/
	docker rm k8s-ubuntu1804-$*

build/packages/kubernetes/%/rhel-7:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		-t kurl/rhel-7-k8s:$* \
		-f bundles/k8s-rhel7/Dockerfile \
		bundles/k8s-rhel7
	-docker rm -f k8s-rhel7-$* 2>/dev/null
	docker create --name k8s-rhel7-$* kurl/rhel-7-k8s:$*
	mkdir -p build/packages/kubernetes/$*/rhel-7
	docker cp k8s-rhel7-$*:/packages/archives/. build/packages/kubernetes/$*/rhel-7/
	docker rm k8s-rhel7-$*

build/templates: build/templates/install.tmpl build/templates/join.tmpl build/templates/upgrade.tmpl

.PHONY: code
code: build/templates build/kustomize build/addons

build/bin/server:
	go build -o build/bin/server cmd/server/main.go

.PHONY: web
web: build/templates build/bin/server
	mkdir -p web/build
	cp -r build/templates web
	cp -r build/bin web

watchrsync:
	bin/watchrsync.js

.PHONY: kurl-util-image
kurl-util-image:
	docker build -t replicated/kurl-util -f deploy/kurl-util/Dockerfile .
