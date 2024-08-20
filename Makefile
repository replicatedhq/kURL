SHELL := /bin/bash
KURL_UTIL_IMAGE ?= replicated/kurl-util:alpha
KURL_BIN_UTILS_FILE ?= kurl-bin-utils-latest.tar.gz
VERSION_PACKAGE = github.com/replicatedhq/kurl/pkg/version
VERSION_TAG ?= 0.0.1
DATE = `date -u +"%Y-%m-%dT%H:%M:%SZ"`
BUILDTAGS = netgo containers_image_ostree_stub exclude_graphdriver_devicemapper exclude_graphdriver_btrfs containers_image_openpgp
BUILDFLAGS = -tags "$(BUILDTAGS)" -installsuffix netgo
KURL_KINDS_VERSION := $(shell grep "github.com/replicatedhq/kurlkinds" go.mod | cut -d ' ' -f2)
COMMIT_ID?=


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


# support for building on macos
SED_INPLACE=-i
SKIP_LDD_CHECK=${SKIP_DYNAMIC_CHECK}
ifeq "darwin" "$(shell uname | tr '[:upper:]' '[:lower:]')"
SED_INPLACE=-i.bak
SKIP_LDD_CHECK=1
endif

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: clean
clean: ## Clean the build directory
	rm -rf build tmp dist

dist/common.tar.gz: build/kustomize build/manifests build/shared build/krew build/kurlkinds build/helm
	mkdir -p dist
	tar cf dist/common.tar -C build kustomize
	tar rf dist/common.tar -C build manifests
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
	bin/save-manifest-assets.sh "velero-$*" addons/velero/$*/Manifest $(CURDIR)/build/addons/velero/$*
	mkdir -p dist
	tar cf - -C build addons/velero/$* | gzip > dist/velero-$*.tar.gz

dist/openebs-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "openebs-$*" addons/openebs/$*/Manifest $(CURDIR)/build/addons/openebs/$*
	mkdir -p dist
	tar cf - -C build addons/openebs/$* | gzip > dist/openebs-$*.tar.gz

dist/minio-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "minio-$*" addons/minio/$*/Manifest $(CURDIR)/build/addons/minio/$*
	mkdir -p dist
	tar cf - -C build addons/minio/$* | gzip > dist/minio-$*.tar.gz

dist/weave-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "weave-$*" addons/weave/$*/Manifest $(CURDIR)/build/addons/weave/$*
	mkdir -p dist
	tar cf - -C build addons/weave/$* | gzip > dist/weave-$*.tar.gz

dist/flannel-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "flannel-$*" addons/flannel/$*/Manifest $(CURDIR)/build/addons/flannel/$*
	mkdir -p dist
	tar cf - -C build addons/flannel/$* | gzip > dist/flannel-$*.tar.gz

dist/antrea-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "antrea-$*" addons/antrea/$*/Manifest $(CURDIR)/build/addons/antrea/$*
	mkdir -p dist
	tar cf - -C build addons/antrea/$* | gzip > dist/antrea-$*.tar.gz

dist/rook-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "rook-$*" addons/rook/$*/Manifest $(CURDIR)/build/addons/rook/$*
	mkdir -p dist
	tar cf - -C build addons/rook/$* | gzip > dist/rook-$*.tar.gz

dist/rookupgrade-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "rookupgrade-$*" addons/rookupgrade/$*/Manifest $(CURDIR)/build/addons/rookupgrade/$*
	mkdir -p dist
	tar cf - -C build addons/rookupgrade/$* | gzip > dist/rookupgrade-$*.tar.gz

dist/contour-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "contour-$*" addons/contour/$*/Manifest $(CURDIR)/build/addons/contour/$*
	mkdir -p dist
	tar cf - -C build addons/contour/$* | gzip > dist/contour-$*.tar.gz

dist/registry-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "registry-$*" addons/registry/$*/Manifest $(CURDIR)/build/addons/registry/$*
	mkdir -p dist
	tar cf - -C build addons/registry/$* | gzip > dist/registry-$*.tar.gz

dist/prometheus-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "prometheus-$*" addons/prometheus/$*/Manifest $(CURDIR)/build/addons/prometheus/$*
	mkdir -p dist
	tar cf - -C build addons/prometheus/$* | gzip > dist/prometheus-$*.tar.gz

dist/fluentd-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "fluentd-$*" addons/fluentd/$*/Manifest $(CURDIR)/build/addons/fluentd/$*
	mkdir -p dist
	tar cf - -C build addons/fluentd/$* | gzip > dist/fluentd-$*.tar.gz

dist/ekco-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "ekco-$*" addons/ekco/$*/Manifest build/addons/ekco/$*
	mkdir -p dist
	tar cf - -C build addons/ekco/$* | gzip > dist/ekco-$*.tar.gz

dist/kotsadm-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "kotsadm-$*" addons/kotsadm/$*/Manifest $(CURDIR)/build/addons/kotsadm/$*
	mkdir -p dist
	tar cf - -C build addons/kotsadm/$* | gzip > dist/kotsadm-$*.tar.gz

dist/containerd-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "containerd-$*" addons/containerd/$*/Manifest $(CURDIR)/build/addons/containerd/$*
	mkdir -p dist
	tar cf - -C build addons/containerd/$* | gzip > dist/containerd-$*.tar.gz

dist/cert-manager-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "cert-manager-$*" addons/cert-manager/$*/Manifest $(CURDIR)/build/addons/cert-manager/$*
	mkdir -p dist
	tar cf - -C build addons/cert-manager/$* | gzip > dist/cert-manager-$*.tar.gz

dist/metrics-server-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "metrics-server-$*" addons/metrics-server/$*/Manifest $(CURDIR)/build/addons/metrics-server/$*
	mkdir -p dist
	tar cf - -C build addons/metrics-server/$* | gzip > dist/metrics-server-$*.tar.gz

dist/host-openssl.tar.gz:
	mkdir -p build/packages/host/openssl
	bin/save-manifest-assets.sh "host-openssl" packages/host/openssl/Manifest $(CURDIR)/build/packages/host/openssl
	mkdir -p dist
	tar cf - -C build packages/host/openssl | gzip > dist/host-openssl.tar.gz

dist/host-fio.tar.gz:
	mkdir -p build/packages/host/fio
	bin/save-manifest-assets.sh "host-fio" packages/host/fio/Manifest $(CURDIR)/build/packages/host/fio
	mkdir -p dist
	tar cf - -C build packages/host/fio | gzip > dist/host-fio.tar.gz

dist/host-longhorn.tar.gz:
	mkdir -p build/packages/host/longhorn
	bin/save-manifest-assets.sh "host-longhorn" packages/host/longhorn/Manifest $(CURDIR)/build/packages/host/longhorn
	mkdir -p dist
	tar cf - -C build packages/host/longhorn | gzip > dist/host-longhorn.tar.gz

dist/longhorn-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "longhorn-$*" addons/longhorn/$*/Manifest $(CURDIR)/build/addons/longhorn/$*
	mkdir -p dist
	tar cf - -C build addons/longhorn/$* | gzip > dist/longhorn-$*.tar.gz

dist/sonobuoy-%.tar.gz: build/addons
	bin/save-manifest-assets.sh "sonobuoy-$*" addons/sonobuoy/$*/Manifest $(CURDIR)/build/addons/sonobuoy/$*
	mkdir -p dist
	tar cf - -C build addons/sonobuoy/$* | gzip > dist/sonobuoy-$*.tar.gz

dist/goldpinger-%.tar.gz: build/addons
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
	${MAKE} build/packages/kubernetes/$*/ubuntu-18.04
	${MAKE} build/packages/kubernetes/$*/ubuntu-20.04
	${MAKE} build/packages/kubernetes/$*/ubuntu-22.04
	${MAKE} build/packages/kubernetes/$*/ubuntu-24.04
	${MAKE} build/packages/kubernetes/$*/rhel-7
	${MAKE} build/packages/kubernetes/$*/rhel-7-force
	${MAKE} build/packages/kubernetes/$*/rhel-8
	${MAKE} build/packages/kubernetes/$*/rhel-9
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
		sed ${SED_INPLACE} 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/install.sh; \
	fi
	chmod +x build/install.sh

build/templates/install.tmpl: build/install.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/install.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^FALLBACK_URL=.*/FALLBACK_URL="{{= FALLBACK_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^ROOK_STEP_VERSIONS=.*/ROOK_STEP_VERSIONS={{= ROOK_STEP_VERSIONS }}/' | \
		sed 's/^CONTAINERD_STEP_VERSIONS=.*/CONTAINERD_STEP_VERSIONS={{= CONTAINERD_STEP_VERSIONS }}/' | \
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
		sed ${SED_INPLACE} 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/join.sh; \
	fi
	chmod +x build/join.sh

build/templates/join.tmpl: build/join.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/join.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^FALLBACK_URL=.*/FALLBACK_URL="{{= FALLBACK_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^ROOK_STEP_VERSIONS=.*/ROOK_STEP_VERSIONS={{= ROOK_STEP_VERSIONS }}/' | \
		sed 's/^CONTAINERD_STEP_VERSIONS=.*/CONTAINERD_STEP_VERSIONS={{= CONTAINERD_STEP_VERSIONS }}/' | \
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
		sed ${SED_INPLACE} 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/upgrade.sh; \
	fi
	chmod +x ./build/upgrade.sh

build/templates/upgrade.tmpl: build/upgrade.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/upgrade.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^FALLBACK_URL=.*/FALLBACK_URL="{{= FALLBACK_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^ROOK_STEP_VERSIONS=.*/ROOK_STEP_VERSIONS={{= ROOK_STEP_VERSIONS }}/' | \
		sed 's/^CONTAINERD_STEP_VERSIONS=.*/CONTAINERD_STEP_VERSIONS={{= CONTAINERD_STEP_VERSIONS }}/' | \
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
		sed ${SED_INPLACE} 's/^KURL_INSTALL_DIRECTORY=.*/KURL_INSTALL_DIRECTORY=\.\/kurl/' build/tasks.sh; \
	fi
	chmod +x build/tasks.sh

build/templates/tasks.tmpl: build/tasks.sh
	mkdir -p build/templates
	sed 's/^KURL_URL=.*/KURL_URL="{{= KURL_URL }}"/' "build/tasks.sh" | \
		sed 's/^DIST_URL=.*/DIST_URL="{{= DIST_URL }}"/' | \
		sed 's/^FALLBACK_URL=.*/FALLBACK_URL="{{= FALLBACK_URL }}"/' | \
		sed 's/^INSTALLER_ID=.*/INSTALLER_ID="{{= INSTALLER_ID }}"/' | \
		sed 's/^KURL_VERSION=.*/KURL_VERSION="{{= KURL_VERSION }}"/' | \
		sed 's/^REPLICATED_APP_URL=.*/REPLICATED_APP_URL="{{= REPLICATED_APP_URL }}"/' | \
		sed 's/^STEP_VERSIONS=.*/STEP_VERSIONS={{= STEP_VERSIONS }}/' | \
		sed 's/^ROOK_STEP_VERSIONS=.*/ROOK_STEP_VERSIONS={{= ROOK_STEP_VERSIONS }}/' | \
		sed 's/^CONTAINERD_STEP_VERSIONS=.*/CONTAINERD_STEP_VERSIONS={{= CONTAINERD_STEP_VERSIONS }}/' | \
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
	curl -fs -o build/kurlkinds/cluster.kurl.sh_installers.yaml \
		https://raw.githubusercontent.com/replicatedhq/kurlkinds/$(KURL_KINDS_VERSION)/config/crds/v1beta1/cluster.kurl.sh_installers.yaml

build/kustomize:
	mkdir -p build
	cp -r scripts/kustomize build/

build/manifests:
	mkdir -p build
	cp -r scripts/manifests build/

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

build/packages/kubernetes/%/ubuntu-18.04:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
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
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
		-t kurl/ubuntu-2004-k8s:$* \
		-f bundles/k8s-ubuntu2004/Dockerfile \
		bundles/k8s-ubuntu2004
	-docker rm -f k8s-ubuntu2004-$* 2>/dev/null
	docker create --name k8s-ubuntu2004-$* kurl/ubuntu-2004-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-20.04
	docker cp k8s-ubuntu2004-$*:/packages/archives/. build/packages/kubernetes/$*/ubuntu-20.04/
	docker rm k8s-ubuntu2004-$*

build/packages/kubernetes/%/ubuntu-22.04:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
		-t kurl/ubuntu-2204-k8s:$* \
		-f bundles/k8s-ubuntu2204/Dockerfile \
		bundles/k8s-ubuntu2204
	-docker rm -f k8s-ubuntu2204-$* 2>/dev/null
	docker create --name k8s-ubuntu2204-$* kurl/ubuntu-2204-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-22.04
	docker cp k8s-ubuntu2204-$*:/packages/archives/. build/packages/kubernetes/$*/ubuntu-22.04/
	docker rm k8s-ubuntu2204-$*

build/packages/kubernetes/%/ubuntu-24.04:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
		-t kurl/ubuntu-2404-k8s:$* \
		-f bundles/k8s-ubuntu2404/Dockerfile \
		bundles/k8s-ubuntu2404
	-docker rm -f k8s-ubuntu2404-$* 2>/dev/null
	docker create --name k8s-ubuntu2404-$* kurl/ubuntu-2404-k8s:$*
	mkdir -p build/packages/kubernetes/$*/ubuntu-24.04
	docker cp k8s-ubuntu2404-$*:/archives/. build/packages/kubernetes/$*/ubuntu-24.04/
	docker rm k8s-ubuntu2404-$*

build/packages/kubernetes/%/rhel-7:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
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
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
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
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
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

build/packages/kubernetes/%/rhel-9:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
		-t kurl/rhel-9-k8s:$* \
		-f bundles/k8s-rhel9/Dockerfile \
		bundles/k8s-rhel9
	-docker rm -f k8s-rhel9-$* 2>/dev/null
	docker create --name k8s-rhel9-$* kurl/rhel-9-k8s:$*
	mkdir -p build/packages/kubernetes/$*/rhel-9
	docker cp k8s-rhel9-$*:/packages/archives/. build/packages/kubernetes/$*/rhel-9/
	find build/packages/kubernetes/$*/rhel-9 | grep kubelet | grep -v kubelet-$* | xargs rm -vf
	find build/packages/kubernetes/$*/rhel-9 | grep kubectl | grep -v kubectl-$* | xargs rm -vf
	docker rm k8s-rhel9-$*

build/packages/kubernetes/%/amazon-2023:
	docker build \
		--build-arg KUBERNETES_VERSION=$* \
		--build-arg KUBERNETES_MINOR_VERSION=$(shell echo $* | sed 's/\.[0-9]*$$//') \
		-t kurl/amazon-2023-k8s:$* \
		-f bundles/k8s-amazon2023/Dockerfile \
		bundles/k8s-amazon2023
	-docker rm -f k8s-amazon2023-$* 2>/dev/null
	docker create --name k8s-amazon2023-$* kurl/amazon-2023-k8s:$*
	mkdir -p build/packages/kubernetes/$*/amazon-2023
	docker cp k8s-amazon2023-$*:/packages/archives/. build/packages/kubernetes/$*/amazon-2023/
	find build/packages/kubernetes/$*/amazon-2023 | grep kubelet | grep -v kubelet-$* | xargs rm -vf
	find build/packages/kubernetes/$*/amazon-2023 | grep kubectl | grep -v kubectl-$* | xargs rm -vf
	docker rm k8s-amazon2023-$*

build/templates: build/templates/install.tmpl build/templates/join.tmpl build/templates/upgrade.tmpl build/templates/tasks.tmpl

.PHONY: build/bin ## Build kurl binary
build/bin: build/bin/kurl
	rm -rf kurl_util/bin
	${MAKE} -C kurl_util build
	cp -r kurl_util/bin build

build/bin/kurl: pkg/cli/commands.go go.mod go.sum
	CGO_ENABLED=0 go build $(LDFLAGS) -o build/bin/kurl $(BUILDFLAGS) ./cmd/kurl
	[ -n "${SKIP_LDD_CHECK}" ] || ldd build/bin/kurl 2>&1 | grep -q "not a dynamic executable" # confirm that there are no linked libs

.PHONY: code
code: build/kustomize build/manifests build/addons ## Build kustomize and addons

.PHONY: scripts
scripts: build/install.sh build/join.sh build/upgrade.sh build/tasks.sh ## Build scripts (install.sh,join.sh,upgrade.sh,tasks.sh)

.PHONY: binaries
binaries: build/krew build/kurlkinds build/helm build/bin ## Build binaries (krew,kinds,helm,kurl)

##@ Development

.PHONY: generate-mocks
generate-mocks: ## Generate mocks tests for CLI and preflight. More info: https://github.com/golang/mock
	go install github.com/golang/mock/mockgen@v1.6.0
	mockgen -source=pkg/cli/cli.go -destination=pkg/cli/mock/mock_cli.go
	mockgen -source=pkg/preflight/runner.go -destination=pkg/preflight/mock/mock_runner.go

.PHONY: kurl-util-image
kurl-util-image: ## Download Kurl util image (replicated/kurl-util:alpha)
	docker pull $(KURL_UTIL_IMAGE)

##@ Remote Development Tests

# NOTE: Before resync you must ensure that the go environment variables are configured with
# the values which are supported by the project:
# export GOOS=linux
# export GOARCH=amd64 # You do not need to export this one if your local env is amd64 already
# export REMOTES="USER@TARGET_SERVER_IP" # Add here the ssh credentials to connect to the remote server
.PHONY: watchrsync
watchrsync: ## Syncronize the code with a remote server. More info: CONTRIBUTING.md
	bin/watchrsync.js

##@ Tests

GOLANGCI_LINT = $(shell go env GOPATH)/bin/golangci-lint
golangci-lint:
	@[ -f $(GOLANGCI_LINT) ] || { \
	set -e ;\
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b  $(shell go env GOPATH)/bin v1.55.2 ;\
	}

.PHONY: lint
lint: golangci-lint ## Run golangci-lint and vet linter
	$(GOLANGCI_LINT) --build-tags "${BUILDTAGS}" run --timeout 10m ./cmd/... ./pkg/... ./kurl_util/...

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint linter and perform small fixes
	$(GOLANGCI_LINT) --build-tags "${BUILDTAGS}" run --fix --timeout 10m ./cmd/... ./pkg/... ./kurl_util/...

.PHONY: vet
vet: ## Go vet the code
	go vet ${BUILDFLAGS} ./cmd/... ./pkg/...

.PHONY: test
test: lint vet ## Check the code with linters and vet
	go test ${BUILDFLAGS} ./cmd/... ./pkg/...
	@## Avoid merge accidentally changes into the scripts/Manifest file
	@cmp --silent ./hack/testdata/manifest/clean ./scripts/Manifest \
	&& echo '### SUCCESS: No changes merged on the script/Manifests! ###' \
	|| (echo '### ERROR: You cannot merge changes on the script manifest!. If you want change the spec please ensure that you also change the ./hack/testdata/manifest/clean file. ###'; exit 1);

/usr/local/bin/shunit2:
	curl -LO https://raw.githubusercontent.com/kward/shunit2/v2.1.8/shunit2
	install -d /usr/local/bin
	install shunit2 /usr/local/bin/shunit2

.PHONY: docker-test-shell
docker-test-shell: ## Run tests for code in shell but containerized. (Used in build-test github action)
	docker build -t kurl-test-shell-rhel-7 -f hack/test-shell/Dockerfile.rhel-7 hack/test-shell
	docker build -t kurl-test-shell-rhel-8 -f hack/test-shell/Dockerfile.rhel-8 hack/test-shell
	docker build -t kurl-test-shell-rhel-9 -f hack/test-shell/Dockerfile.rhel-9 hack/test-shell
	docker build -t kurl-test-shell-ubuntu-20.04 -f hack/test-shell/Dockerfile.ubuntu-20.04 hack/test-shell
	docker build -t kurl-test-shell-ubuntu-22.04 -f hack/test-shell/Dockerfile.ubuntu-22.04 hack/test-shell
	docker run -i --rm -v `pwd`:/src kurl-test-shell-rhel-7 make /usr/local/bin/shunit2 test-shell
	docker run -i --rm -v `pwd`:/src kurl-test-shell-rhel-8 make /usr/local/bin/shunit2 test-shell
	docker run -i --rm -v `pwd`:/src kurl-test-shell-rhel-9 make /usr/local/bin/shunit2 test-shell
	docker run -i --rm -v `pwd`:/src kurl-test-shell-ubuntu-20.04 make /usr/local/bin/shunit2 test-shell
	docker run -i --rm -v `pwd`:/src kurl-test-shell-ubuntu-22.04 make /usr/local/bin/shunit2 test-shell

# More info about how to install shUnit2
# https://alexharv074.github.io/2017/07/07/unit-testing-a-bash-script-with-shunit2.html
# For mac os you can run brew install shunit2
.PHONY: test-shell
test-shell: ## Run tests for code in shell. (Requires shUnit2 to be installed).
	# TODO:
	#   - find tests
	#   - add to ci
	./scripts/common/addon-test.sh
	./scripts/common/common-test.sh
	./scripts/common/kubernetes-test.sh
	./scripts/common/proxy-test.sh
	./scripts/common/yaml-test.sh
	./scripts/common/rook-upgrade-test.sh
	./addons/rook/template/test/install.sh
	./scripts/common/test/common-test.sh
	./scripts/common/test/discover-test.sh
	./scripts/common/test/docker-version-test.sh
	./scripts/common/test/ip-address-test.sh
	./scripts/common/test/semver-test.sh

##@ Release

.PHONY: generate-addons ## Generate the addons when we deploy to staging and production.
generate-addons:
	node bin/generate-addons.js

.PHONY: init-sbom
init-sbom:
	mkdir -p sbom/spdx sbom/assets

.PHONY: install-spdx-sbom-generator
install-spdx-sbom-generator: init-sbom
ifeq (,$(shell command -v spdx-sbom-generator))
	./scripts/initialize-build.sh
SPDX_GENERATOR=./sbom/spdx-sbom-generator
else
SPDX_GENERATOR=$(shell command -v spdx-sbom-generator)
endif

.PHONY: generate-sbom
generate-sbom: install-spdx-sbom-generator ## Generate Signed SBOMs dependencies tar file
	$(SPDX_GENERATOR) -o ./sbom/spdx        

sbom/assets/kurl-sbom.tgz: generate-sbom
	tar -czf sbom/assets/kurl-sbom.tgz sbom/spdx/*.spdx

sbom: sbom/assets/kurl-sbom.tgz
	cosign sign-blob -key ./cosign.key sbom/assets/kurl-sbom.tgz > ./sbom/assets/kurl-sbom.tgz.sig
	cosign public-key -key ./cosign.key -outfile ./sbom/assets/key.pub

.PHONY: tag-and-release
tag-and-release: ## Create tags and release
ifneq "$(COMMIT_ID)" ""
	@./bin/tag-and-release.sh --commit-id=$(COMMIT_ID)
else
	@./bin/tag-and-release.sh
endif
