SHELL := /bin/bash
KURL_UTIL_IMAGE ?= replicated/kurl-util:alpha
KURL_BIN_UTILS_FILE ?= kurl-bin-utils-latest.tar.gz
VERSION_PACKAGE = github.com/replicatedhq/kurl/pkg/version
VERSION_TAG ?= 0.0.1
DATE = `date -u +"%Y-%m-%dT%H:%M:%SZ"`
BUILDFLAGS = -tags "netgo containers_image_ostree_stub exclude_graphdriver_devicemapper exclude_graphdriver_btrfs containers_image_openpgp" -installsuffix netgo

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
	-s -w \
	-X ${VERSION_PACKAGE}.version=${VERSION_TAG} \
	-X ${VERSION_PACKAGE}.gitSHA=${GIT_SHA} \
	-X ${VERSION_PACKAGE}.buildTime=${DATE} \
"
endef


.PHONY: clean
clean:
	rm -rf build tmp dist

dist/common.tar.gz: build/kustomize build/shared build/krew build/kurlkinds build/helm
	mkdir -p dist
	tar cf dist/common.tar -C build kustomize
	tar rf dist/common.tar -C build shared
	tar rf dist/common.tar -C build krew
	tar rf dist/common.tar -C build kurlkinds
	tar rf dist/common.tar -C build helm
	gzip dist/common.tar

dist/kurl-bin-utils-%.tar.gz: build/bin
	mkdir -p dist
	tar -C ./build -czvf ./dist/kurl-bin-utils-$*.tar.gz bin

dist/aws-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh "aws-$*" addons/aws/$*/Manifest build/addons/aws/$*
	tar cf - -C build addons/aws/$* | gzip > dist/aws-$*.tar.gz

dist/collectd-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh "collectd-$*" addons/collectd/$*/Manifest build/addons/collectd/$*
	tar cf - -C build addons/collectd/$* | gzip > dist/collectd-$*.tar.gz

dist/nodeless-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh "nodeless-$*" addons/nodeless/$*/Manifest $(CURDIR)/build/addons/nodeless/$*
	tar cf - -C build addons/nodeless/$* | gzip > dist/nodeless-$*.tar.gz

dist/calico-%.tar.gz: build/addons
	mkdir -p dist
	bin/save-manifest-assets.sh "calico-$*" addons/calico/$*/Manifest $(CURDIR)/build/addons/calico/$*
	tar cf - -C build addons/calico/$* | gzip > dist/calico-$*.tar.gz

dist/velero-%.tar.gz: build/addons
	mkdir -p build/addons/velero/$*/images
	bin/save-manifest-assets.sh "velero-$*" addons/velero/$*/Manifest $(CURDIR)/build/addons/velero/$*
	mkdir -p dist
	tar cf - -C build addons/velero/$* | gzip > dist/velero-$*.tar.gz

dist/openebs-%.tar.gz: build/addons
	mkdir -p build/addons/openebs/$*/images
	bin/save-manifest-assets.sh "openebs-$*" addons/openebs/$*/Manifest $(CURDIR)/build/addons/openebs/$*
	mkdir -p dist
	tar cf - -C build addons/openebs/$* | gzip > dist/openebs-$*.tar.gz

dist/minio-%.tar.gz: build/addons
	mkdir -p build/addons/minio/$*/images
	bin/save-manifest-assets.sh "minio-$*" addons/minio/$*/Manifest $(CURDIR)/build/addons/minio/$*
	mkdir -p dist
	tar cf - -C build addons/minio/$* | gzip > dist/minio-$*.tar.gz

dist/weave-%.tar.gz: build/addons
	mkdir -p build/addons/weave/$*/images
	bin/save-manifest-assets.sh "weave-$*" addons/weave/$*/Manifest $(CURDIR)/build/addons/weave/$*
	mkdir -p dist
	tar cf - -C build addons/weave/$* | gzip > dist/weave-$*.tar.gz

dist/antrea-%.tar.gz: build/addons
	mkdir -p build/addons/antrea/$*/images
	bin/save-manifest-assets.sh "antrea-$*" addons/antrea/$*/Manifest $(CURDIR)/build/addons/antrea/$*
	mkdir -p dist
	tar cf - -C build addons/antrea/$* | gzip > dist/antrea-$*.tar.gz

dist/rook-%.tar.gz: build/addons
	mkdir -p build/addons/rook/$*/images
	bin/save-manifest-assets.sh "rook-$*" addons/rook/$*/Manifest $(CURDIR)/build/addons/rook/$*
	mkdir -p dist
	tar cf - -C build addons/rook/$* | gzip > dist/rook-$*.tar.gz

dist/contour-%.tar.gz: build/addons
	mkdir -p build/addons/contour/$*/images
	bin/save-manifest-assets.sh "contour-$*" addons/contour/$*/Manifest $(CURDIR)/build/addons/contour/$*
	mkdir -p dist
	tar cf - -C build addons/contour/$* | gzip > dist/contour-$*.tar.gz

dist/registry-%.tar.gz: build/addons
	mkdir -p build/addons/registry/$*/images
	bin/save-manifest-assets.sh "registry-$*" addons/registry/$*/Manifest $(CURDIR)/build/addons/registry/$*
	mkdir -p dist
	tar cf - -C build addons/registry/$* | gzip > dist/registry-$*.tar.gz

dist/prometheus-%.tar.gz: build/addons
	mkdir -p build/addons/prometheus/$*/images
	bin/save-manifest-assets.sh "prometheus-$*" addons/prometheus/$*/Manifest $(CURDIR)/build/addons/prometheus/$*
	mkdir -p dist
	tar cf - -C build addons/prometheus/$* | gzip > dist/prometheus-$*.tar.gz

dist/fluentd-%.tar.gz: build/addons
	mkdir -p build/addons/fluentd/$*/images
	bin/save-manifest-assets.sh "fluentd-$*" addons/fluentd/$*/Manifest $(CURDIR)/build/addons/fluentd/$*
	mkdir -p dist
	tar cf - -C build addons/fluentd/$* | gzip > dist/fluentd-$*.tar.gz

dist/ekco-%.tar.gz: build/addons
	mkdir -p build/addons/ekco/$*/images
	bin/save-manifest-assets.sh "ekco-$*" addons/ekco/$*/Manifest build/addons/ekco/$*
	mkdir -p dist
	tar cf - -C build addons/ekco/$* | gzip > dist/ekco-$*.tar.gz

dist/kotsadm-%.tar.gz: build/addons
	mkdir -p build/addons/kotsadm/$*/images
	bin/save-manifest-assets.sh "kotsadm-$*" addons/kotsadm/$*/Manifest $(CURDIR)/build/addons/kotsadm/$*
	mkdir -p dist
	tar cf - -C build addons/kotsadm/$* | gzip > dist/kotsadm-$*.tar.gz

dist/docker-%.tar.gz:
	${MAKE} build/packages/docker/$*/ubuntu-16.04
	${MAKE} build/packages/docker/$*/ubuntu-18.04
	${MAKE} build/packages/docker/$*/ubuntu-20.04
	${MAKE} build/packages/docker/$*/rhel-7
	${MAKE} build/packages/docker/$*/rhel-7-force
	${MAKE} build/packages/docker/$*/rhel-8
	mkdir -p dist
	curl -L https://github.com/opencontainers/runc/releases/download/v1.0.0-rc95/runc.amd64 > build/packages/docker/$*/runc
	chmod +x build/packages/docker/$*/runc
	tar cf - -C build packages/docker/$* | gzip > dist/docker-$*.tar.gz

dist/containerd-%.tar.gz: build/addons
	mkdir -p build/addons/containerd/$*/assets
	bin/save-manifest-assets.sh "containerd-$*" addons/containerd/$*/Manifest $(CURDIR)/build/addons/containerd/$*
	mkdir -p dist
	tar cf - -C build addons/containerd/$* | gzip > dist/containerd-$*.tar.gz

dist/cert-manager-%.tar.gz: build/addons
	mkdir -p build/addons/cert-manager/$*/assets
	bin/save-manifest-assets.sh "cert-manager-$*" addons/cert-manager/$*/Manifest $(CURDIR)/build/addons/cert-manager/$*
	mkdir -p dist
	tar cf - -C build addons/cert-manager/$* | gzip > dist/cert-manager-$*.tar.gz

dist/metrics-server-%.tar.gz: build/addons
	mkdir -p build/addons/metrics-server/$*/assets
	bin/save-manifest-assets.sh "metrics-server-$*" addons/metrics-server/$*/Manifest $(CURDIR)/build/addons/metrics-server/$*
	mkdir -p dist
	tar cf - -C build addons/metrics-server/$* | gzip > dist/metrics-server-$*.tar.gz

dist/host-openssl.tar.gz:
	mkdir -p build/packages/host/openssl
	bin/save-manifest-assets.sh "host-openssl" packages/host/openssl/Manifest $(CURDIR)/build/packages/host/openssl
	mkdir -p dist
	tar cf - -C build packages/host/openssl | gzip > dist/host-openssl.tar.gz

dist/longhorn-%.tar.gz: build/addons
	mkdir -p build/addons/longhorn/$*/images
	bin/save-manifest-assets.sh "longhorn-$*" addons/longhorn/$*/Manifest $(CURDIR)/build/addons/longhorn/$*
	mkdir -p dist
	tar cf - -C build addons/longhorn/$* | gzip > dist/longhorn-$*.tar.gz

dist/sonobuoy-%.tar.gz: build/addons
	mkdir -p build/addons/sonobuoy/$*/images
	bin/save-manifest-assets.sh "sonobuoy-$*" addons/sonobuoy/$*/Manifest $(CURDIR)/build/addons/sonobuoy/$*
	mkdir -p dist
	tar cf - -C build addons/sonobuoy/$* | gzip > dist/sonobuoy-$*.tar.gz

dist/goldpinger-%.tar.gz: build/addons
	mkdir -p build/addons/goldpinger/$*/images
	bin/save-manifest-assets.sh "goldpinger-$*" addons/goldpinger/$*/Manifest $(CURDIR)/build/addons/goldpinger/$*
	mkdir -p dist
	tar cf - -C build addons/goldpinger/$* | gzip > dist/goldpinger-$*.tar.gz


dist/kubernetes-%.tar.gz:
	# conformance packages do not exist for versions of k8s prior to 1.17
	$(eval major = $(shell echo "$*" | sed -E 's/^v?([0-9]+)\.([0-9]+).*$$/\1/'))
	$(eval minor = $(shell echo "$*" | sed -E 's/^v?([0-9]+)\.([0-9]+).*$$/\2/'))
	[ "${major}" -eq "1" ] && [ "${minor}" -ge "17" ] && { \
		${MAKE} dist/kubernetes-conformance-$*.tar.gz ; \
	} || true ;
	${MAKE} build/packages/kubernetes/$*/images
	${MAKE} build/packages/kubernetes/$*/ubuntu-16.04
	${MAKE} build/packages/kubernetes/$*/ubuntu-18.04
	${MAKE} build/packages/kubernetes/$*/ubuntu-20.04
	${MAKE} build/packages/kubernetes/$*/rhel-7
	${MAKE} build/packages/kubernetes/$*/rhel-7-force
	${MAKE} build/packages/kubernetes/$*/rhel-8
	cp packages/kubernetes/$*/Manifest build/packages/kubernetes/$*/
	mkdir -p dist
	tar cf - -C build packages/kubernetes/$* | gzip > dist/kubernetes-$*.tar.gz

build/packages/kubernetes/%/images:
	mkdir -p build/packages/kubernetes/$*/images
	bin/save-manifest-assets.sh "kubernetes-images-$*" packages/kubernetes/$*/Manifest build/packages/kubernetes/$*

dist/kubernetes-conformance-%.tar.gz:
	${MAKE} build/packages/kubernetes-conformance/$*/images
	cp packages/kubernetes/$*/conformance/Manifest build/packages/kubernetes-conformance/$*/
	mkdir -p dist
	tar cf - -C build packages/kubernetes-conformance/$* | gzip > dist/kubernetes-conformance-$*.tar.gz

build/packages/kubernetes-conformance/%/images:
	mkdir -p build/packages/kubernetes-conformance/$*/images
	bin/save-manifest-assets.sh "kubernetes-conformance-images-$*" packages/kubernetes/$*/conformance/Manifest build/packages/kubernetes-conformance/$*

dist/rke-2-%.tar.gz:
	${MAKE} dist/kubernetes-conformance-$(shell echo "$*" | sed 's/^v\(.*\)-.*$$/\1/').tar.gz
	${MAKE} build/packages/rke-2/$*/images
	${MAKE} build/packages/rke-2/$*/rhel-7
	${MAKE} build/packages/rke-2/$*/rhel-7-force
	${MAKE} build/packages/rke-2/$*/rhel-8
	cp packages/rke-2/$*/Manifest build/packages/rke-2/$*/
	mkdir -p dist
	tar cf - -C build packages/rke-2/$* | gzip > dist/rke-2-$*.tar.gz

build/packages/rke-2/%/images:
	mkdir -p build/packages/rke-2/$*/images
	bin/save-manifest-assets.sh "rke-2-images-$*" packages/rke-2/$*/Manifest build/packages/rke-2/$*

dist/k-3-s-%.tar.gz:
	${MAKE} dist/kubernetes-conformance-$(shell echo "$*" | sed 's/^v\(.*\)-.*$$/\1/').tar.gz
	${MAKE} build/packages/k-3-s/$*/images
	${MAKE} build/packages/k-3-s/$*/rhel-7
	${MAKE} build/packages/k-3-s/$*/rhel-7-force
	${MAKE} build/packages/k-3-s/$*/rhel-8
	cp packages/k-3-s/$*/Manifest build/packages/k-3-s/$*/
	mkdir -p dist
	tar cf - -C build packages/k-3-s/$* | gzip > dist/k-3-s-$*.tar.gz

build/packages/k-3-s/%/images:
	mkdir -p build/packages/k-3-s/$*/images
	bin/save-manifest-assets.sh "k-3-s-images-$*" packages/k-3-s/$*/Manifest build/packages/k-3-s/$*
	gzip build/packages/k-3-s/$*/assets/k3s-images.linux-amd64.tar 

DEV := 0

build/install.sh: scripts/install.sh
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/install.sh | sed '$$d' > tmp/install.sh
	for script in $(shell cat scripts/install.sh | grep '\. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/install.sh ; \
		echo "" >> tmp/install.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/install.sh | sed '1d' >> tmp/install.sh
	mv tmp/install.sh build/install.sh
	if [ "${DEV}" = "1" ]; then \
		sed -i 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/install.sh; \
	fi
	chmod +x build/install.sh

build/templates/install.tmpl: build/install.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/install.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^INSTALLER_YAML=.*/INSTALLER_YAML="{{= INSTALLER_YAML }}"/' | \
		sed 's/^KURL_UTIL_IMAGE=.*/KURL_UTIL_IMAGE="{{= KURL_UTIL_IMAGE }}"/' | \
		sed 's/^KURL_BIN_UTILS_FILE=.*/KURL_BIN_UTILS_FILE="{{= KURL_BIN_UTILS_FILE }}"/' | \
		sed 's/^DISABLE_REPORTING=.*//' \
		> build/templates/install.tmpl

dist/install.tmpl: build/templates/install.tmpl
	mkdir -p dist
	cp build/templates/install.tmpl dist/install.tmpl

build/join.sh: scripts/join.sh
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/join.sh | sed '$$d' > tmp/join.sh
	for script in $(shell cat scripts/join.sh | grep '\. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/join.sh ; \
		echo "" >> tmp/join.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/join.sh | sed '1d' >> tmp/join.sh
	mv tmp/join.sh build/join.sh
	if [ "${DEV}" = "1" ]; then \
		sed -i 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/join.sh; \
	fi
	chmod +x build/join.sh

build/templates/join.tmpl: build/join.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/join.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^INSTALLER_YAML=.*/INSTALLER_YAML="{{= INSTALLER_YAML }}"/' | \
		sed 's/^KURL_UTIL_IMAGE=.*/KURL_UTIL_IMAGE="{{= KURL_UTIL_IMAGE }}"/' | \
		sed 's/^KURL_BIN_UTILS_FILE=.*/KURL_BIN_UTILS_FILE="{{= KURL_BIN_UTILS_FILE }}"/' | \
		sed 's/^DISABLE_REPORTING=.*//' \
		> build/templates/join.tmpl

dist/join.tmpl: build/templates/join.tmpl
	mkdir -p dist
	cp build/templates/join.tmpl dist/join.tmpl

build/upgrade.sh: scripts/upgrade.sh
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/upgrade.sh | sed '$$d' > tmp/upgrade.sh
	for script in $(shell cat scripts/upgrade.sh | grep '\. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/upgrade.sh ; \
		echo "" >> tmp/upgrade.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/upgrade.sh | sed '1d' >> tmp/upgrade.sh
	mv tmp/upgrade.sh build/upgrade.sh
	if [ "${DEV}" = "1" ]; then \
		sed -i 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/upgrade.sh; \
	fi
	chmod +x ./build/upgrade.sh

build/templates/upgrade.tmpl: build/upgrade.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/upgrade.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^INSTALLER_YAML=.*/INSTALLER_YAML="{{= INSTALLER_YAML }}"/' | \
		sed 's/^KURL_UTIL_IMAGE=.*/KURL_UTIL_IMAGE="{{= KURL_UTIL_IMAGE }}"/' | \
		sed 's/^KURL_BIN_UTILS_FILE=.*/KURL_BIN_UTILS_FILE="{{= KURL_BIN_UTILS_FILE }}"/' | \
		sed 's/^DISABLE_REPORTING=.*//' \
		> build/templates/upgrade.tmpl

dist/upgrade.tmpl: build/templates/upgrade.tmpl
	mkdir -p dist
	cp build/templates/upgrade.tmpl dist/upgrade.tmpl

build/tasks.sh: scripts/tasks.sh
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/tasks.sh | sed '$$d' > tmp/tasks.sh
	for script in $(shell cat scripts/tasks.sh | grep '\. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/tasks.sh ; \
		echo "" >> tmp/tasks.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/tasks.sh | sed '1d' >> tmp/tasks.sh
	mv tmp/tasks.sh build/tasks.sh
	if [ "${DEV}" = "1" ]; then \
		sed -i 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/tasks.sh; \
	fi
	chmod +x build/tasks.sh

build/templates/tasks.tmpl: build/tasks.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/tasks.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^INSTALLER_YAML=.*/INSTALLER_YAML="{{= INSTALLER_YAML }}"/' | \
		sed 's/^KURL_UTIL_IMAGE=.*/KURL_UTIL_IMAGE="{{= KURL_UTIL_IMAGE }}"/' | \
		sed 's/^KURL_BIN_UTILS_FILE=.*/KURL_BIN_UTILS_FILE="{{= KURL_BIN_UTILS_FILE }}"/' | \
		sed 's/^DISABLE_REPORTING=.*//' \
		> build/templates/tasks.tmpl

dist/tasks.tmpl: build/templates/tasks.tmpl
	mkdir -p dist
	cp build/templates/tasks.tmpl dist/tasks.tmpl

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

build/kurlkinds:
	mkdir -p build/kurlkinds
	cp kurlkinds/config/crds/v1beta1/cluster.kurl.sh_installers.yaml build/kurlkinds

build/kustomize:
	mkdir -p build
	cp -r scripts/kustomize build/

build/helm:
	mkdir -p build/helm
	docker build -t helm -f bundles/helm/Dockerfile bundles/helm
	- docker rm -f helm 2>/dev/null
	docker create --name helm helm:latest
	docker cp helm:/helm build/
	docker rm helm

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

build/packages/docker/%/ubuntu-20.04:
	./bundles/docker-ubuntu2004/build.sh $* `pwd`/build/packages/docker/$*/ubuntu-20.04

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

build/packages/docker/18.09.8/rhel-8:
	${MAKE} build/packages/docker/18.09.8/rhel-7-force

build/packages/docker/19.03.4/rhel-8:
	${MAKE} build/packages/docker/19.03.4/rhel-7-force

build/packages/docker/19.03.10/rhel-8:
	${MAKE} build/packages/docker/19.03.10/rhel-7-force

build/packages/docker/%/rhel-7-force:
	docker build \
		--build-arg DOCKER_VERSION=$* \
		-t kurl/rhel-7-force-docker:$* \
		-f bundles/docker-rhel7-force/Dockerfile \
		bundles/docker-rhel7-force
	-docker rm -f docker-rhel7-force 2>/dev/null
	docker create --name docker-rhel7-force-$* kurl/rhel-7-force-docker:$*
	mkdir -p build/packages/docker/$*/rhel-7-force
	docker cp docker-rhel7-force-$*:/packages/archives/. build/packages/docker/$*/rhel-7-force
	docker rm docker-rhel7-force-$*

build/packages/docker/%/rhel-8:
	docker build \
		--build-arg DOCKER_VERSION=$* \
		-t kurl/rhel-8-docker:$* \
		-f bundles/docker-rhel8/Dockerfile \
		bundles/docker-rhel8
	-docker rm -f docker-rhel8 2>/dev/null
	docker create --name docker-rhel8-$* kurl/rhel-8-docker:$*
	mkdir -p build/packages/docker/$*/rhel-8
	docker cp docker-rhel8-$*:/packages/archives/. build/packages/docker/$*/rhel-8
	docker rm docker-rhel8-$*

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

build/packages/kubernetes/%/ubuntu-20.04:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		-t kurl/ubuntu-2004-k8s:$* \
		-f bundles/k8s-ubuntu2004/Dockerfile \
		bundles/k8s-ubuntu2004
	-docker rm -f k8s-ubuntu2004-$* 2>/dev/null
	docker create --name k8s-ubuntu2004-$* kurl/ubuntu-2004-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-20.04
	docker cp k8s-ubuntu2004-$*:/packages/archives/. build/packages/kubernetes/$*/ubuntu-20.04/
	docker rm k8s-ubuntu2004-$*

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

build/packages/kubernetes/%/rhel-7-force:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		-t kurl/rhel-7-force-k8s:$* \
		-f bundles/k8s-rhel7-force/Dockerfile \
		bundles/k8s-rhel7-force
	-docker rm -f k8s-rhel7-force-$* 2>/dev/null
	docker create --name k8s-rhel7-force-$* kurl/rhel-7-force-k8s:$*
	mkdir -p build/packages/kubernetes/$*/rhel-7-force
	docker cp k8s-rhel7-force-$*:/packages/archives/. build/packages/kubernetes/$*/rhel-7-force/
	docker rm k8s-rhel7-force-$*

build/packages/kubernetes/%/rhel-8:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		-t kurl/rhel-8-k8s:$* \
		-f bundles/k8s-rhel8/Dockerfile \
		bundles/k8s-rhel8
	-docker rm -f k8s-rhel8-$* 2>/dev/null
	docker create --name k8s-rhel8-$* kurl/rhel-8-k8s:$*
	mkdir -p build/packages/kubernetes/$*/rhel-8
	docker cp k8s-rhel8-$*:/packages/archives/. build/packages/kubernetes/$*/rhel-8/
	find build/packages/kubernetes/$*/rhel-8 | grep kubelet | grep -v kubelet-$* | xargs rm -vf
	find build/packages/kubernetes/$*/rhel-8 | grep kubectl | grep -v kubectl-$* | xargs rm -vf
	docker rm k8s-rhel8-$*

build/packages/rke-2/%/rhel-7:
	docker build \
		--build-arg RKE2_VERSION=$* \
		-t kurl/rhel-7-rke2:$* \
		-f bundles/rke2-rhel7/Dockerfile \
		bundles/rke2-rhel7
	-docker rm -f rke2-rhel7-$* 2>/dev/null
	docker create --name rke2-rhel7-$* kurl/rhel-7-rke2:$*
	mkdir -p build/packages/rke-2/$*/rhel-7
	docker cp rke2-rhel7-$*:/packages/archives/. build/packages/rke-2/$*/rhel-7/
	docker rm rke2-rhel7-$*

build/packages/rke-2/%/rhel-7-force:
	docker build \
		--build-arg RKE2_VERSION=$* \
		-t kurl/rhel-7-force-rke2:$* \
		-f bundles/rke2-rhel7-force/Dockerfile \
		bundles/rke2-rhel7-force
	-docker rm -f rke2-rhel7-force-$* 2>/dev/null
	docker create --name rke2-rhel7-force-$* kurl/rhel-7-force-rke2:$*
	mkdir -p build/packages/rke-2/$*/rhel-7-force
	docker cp rke2-rhel7-force-$*:/packages/archives/. build/packages/rke-2/$*/rhel-7-force/
	docker rm rke2-rhel7-force-$*

build/packages/rke-2/%/rhel-8:
	docker build \
		--build-arg RKE2_VERSION=$* \
		-t kurl/rhel-8-rke2:$* \
		-f bundles/rke2-rhel8/Dockerfile \
		bundles/rke2-rhel8
	-docker rm -f rke2-rhel8-$* 2>/dev/null
	docker create --name rke2-rhel8-$* kurl/rhel-8-rke2:$*
	mkdir -p build/packages/rke-2/$*/rhel-8
	docker cp rke2-rhel8-$*:/packages/archives/. build/packages/rke-2/$*/rhel-8/
	docker rm rke2-rhel8-$*

build/packages/k-3-s/%/rhel-7:
	docker build \
		--build-arg K3S_VERSION=$* \
		-t kurl/rhel-7-k3s:$* \
		-f bundles/k3s-rhel7/Dockerfile \
		bundles/k3s-rhel7
	-docker rm -f k3s-rhel7-$* 2>/dev/null
	docker create --name k3s-rhel7-$* kurl/rhel-7-k3s:$*
	mkdir -p build/packages/k-3-s/$*/rhel-7
	docker cp k3s-rhel7-$*:/packages/archives/. build/packages/k-3-s/$*/rhel-7/
	docker rm k3s-rhel7-$*

build/packages/k-3-s/%/rhel-7-force:
	docker build \
		--build-arg K3S_VERSION=$* \
		-t kurl/rhel-7-force-k3s:$* \
		-f bundles/k3s-rhel7-force/Dockerfile \
		bundles/k3s-rhel7-force
	-docker rm -f k3s-rhel7-force-$* 2>/dev/null
	docker create --name k3s-rhel7-force-$* kurl/rhel-7-force-k3s:$*
	mkdir -p build/packages/k-3-s/$*/rhel-7-force
	docker cp k3s-rhel7-force-$*:/packages/archives/. build/packages/k-3-s/$*/rhel-7-force/
	docker rm k3s-rhel7-force-$*

build/packages/k-3-s/%/rhel-8:
	docker build \
		--build-arg K3S_VERSION=$* \
		-t kurl/rhel-8-k3s:$* \
		-f bundles/k3s-rhel8/Dockerfile \
		bundles/k3s-rhel8
	-docker rm -f k3s-rhel8-$* 2>/dev/null
	docker create --name k3s-rhel8-$* kurl/rhel-8-k3s:$*
	mkdir -p build/packages/k-3-s/$*/rhel-8
	docker cp k3s-rhel8-$*:/packages/archives/. build/packages/k-3-s/$*/rhel-8/
	docker rm k3s-rhel8-$*

build/templates: build/templates/install.tmpl build/templates/join.tmpl build/templates/upgrade.tmpl build/templates/tasks.tmpl

build/bin: build/bin/kurl
	rm -rf kurl_util/bin
	${MAKE} -C kurl_util build
	cp -r kurl_util/bin build

build/bin/kurl:
	CGO_ENABLED=0 go build $(LDFLAGS) -o build/bin/kurl $(BUILDFLAGS) ./cmd/kurl
	ldd build/bin/kurl | grep -q "not a dynamic executable" # confirm that there are no linked libs

.PHONY: code
code: build/kustomize build/addons

build/bin/server: cmd/server/main.go
	go build -o build/bin/server cmd/server/main.go

.PHONY: web
web: build/bin/server
	mkdir -p web/build
	cp -r build/bin web

watchrsync:
	bin/watchrsync.js

.PHONY: deps
deps:
	go get golang.org/x/lint/golint

.PHONY: lint
lint:
	golint ./cmd/... ./pkg/... # TODO -set_exit_status

.PHONY: vet
vet:
	go vet ${BUILDFLAGS} ./cmd/... ./pkg/...

.PHONY: test
test: lint vet
	go test ${BUILDFLAGS} ./cmd/... ./pkg/...

.PHONY: test-shell
test-shell:
	# TODO:
	#   - find tests
	#   - add to ci
	./scripts/distro/rke2/distro-test.sh
	./scripts/common/common-test.sh
	./scripts/common/docker-test.sh
	./scripts/common/kubernetes-test.sh

.PHONY: kurl-util-image
kurl-util-image:
	docker pull $(KURL_UTIL_IMAGE)

.PHONY: generate-addons
generate-addons:
	make -C web generate-versions
	node generate-addons.js

.PHONY: generate-mocks
generate-mocks:
	mockgen -source=pkg/cli/cli.go -destination=pkg/cli/mock/mock_cli.go
	mockgen -source=pkg/preflight/runner.go -destination=pkg/preflight/mock/mock_runner.go

.PHONY: shunit2
shunit2: common-test #TODO include other tests

.PHONY: common-test
common-test:
	./scripts/common/test/common-test.sh
