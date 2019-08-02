.PHONY: clean deps code
SHELL := /bin/bash

include Manifest

clean:
	rm -rf build tmp dist

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :


build: code build/ubuntu-16.04 build/ubuntu-18.04 build/rhel-7 build/k8s-images.tar

code: build/install.sh build/join.sh build/yaml

build/install.sh:
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/install.sh | sed '$$d' > tmp/install.sh
	for script in $(shell cat scripts/install.sh | grep '. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/install.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/install.sh | sed '1d' >> tmp/install.sh
	mv tmp/install.sh build/install.sh

build/join.sh:
	mkdir -p tmp build
	sed '/# Magic begin/q' scripts/join.sh | sed '$$d' > tmp/join.sh
	for script in $(shell cat scripts/join.sh | grep '. $$DIR/' | sed 's/. $$DIR\///'); do \
		cat $$script >> tmp/join.sh ; \
	done
	sed -n '/# Magic end/,$$p' scripts/join.sh | sed '1d' >> tmp/join.sh
	mv tmp/join.sh build/join.sh

build/yaml:
	mkdir -p build
	cp -r yaml build/

build/ubuntu-16.04: build/ubuntu-16.04/packages/docker build/ubuntu-16.04/packages/k8s

build/ubuntu-18.04: build/ubuntu-18.04/packages/docker build/ubuntu-18.04/packages/k8s

build/rhel-7: build/rhel-7/packages/docker build/rhel-7/packages/k8s

build/ubuntu-16.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t kurl/ubuntu-1604-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1604/Dockerfile \
		bundles/docker-ubuntu1604
	-docker rm -f docker-ubuntu1604 2>/dev/null
	docker create --name docker-ubuntu1604 kurl/ubuntu-1604-docker:${DOCKER_VERSION}
	mkdir -p build/ubuntu-16.04/packages/docker
	docker cp docker-ubuntu1604:/packages/archives/. build/ubuntu-16.04/packages/docker/
	docker rm docker-ubuntu1604

build/ubuntu-18.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t kurl/ubuntu-1804-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1804/Dockerfile \
		bundles/docker-ubuntu1804
	-docker rm -f docker-ubuntu1804 2>/dev/null
	docker create --name docker-ubuntu1804 kurl/ubuntu-1804-docker:${DOCKER_VERSION}
	mkdir -p build/ubuntu-18.04/packages/docker
	docker cp docker-ubuntu1804:/packages/archives/. build/ubuntu-18.04/packages/docker/
	docker rm docker-ubuntu1804

build/rhel-7/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t kurl/rhel-7-docker:${DOCKER_VERSION} \
		-f bundles/docker-rhel7/Dockerfile \
		bundles/docker-rhel7
	-docker rm -f docker-rhel7 2>/dev/null
	docker create --name docker-rhel7 kurl/rhel-7-docker:${DOCKER_VERSION}
	mkdir -p build/rhel-7/packages/docker
	docker cp docker-rhel7:/packages/archives/. build/rhel-7/packages/docker/
	docker rm docker-rhel7

build/ubuntu-16.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t kurl/ubuntu-1604-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1604/Dockerfile \
		bundles/k8s-ubuntu1604
	-docker rm -f k8s-ubuntu1604 2>/dev/null
	docker create --name k8s-ubuntu1604 kurl/ubuntu-1604-k8s:${KUBERNETES_VERSION}
	mkdir -p build/ubuntu-16.04/packages/k8s
	docker cp k8s-ubuntu1604:/packages/archives/. build/ubuntu-16.04/packages/k8s/
	docker rm k8s-ubuntu1604

build/ubuntu-18.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t kurl/ubuntu-1804-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1804/Dockerfile \
		bundles/k8s-ubuntu1804
	-docker rm -f k8s-ubuntu1804 2>/dev/null
	docker create --name k8s-ubuntu1804 kurl/ubuntu-1804-k8s:${KUBERNETES_VERSION}
	mkdir -p build/ubuntu-18.04/packages/k8s
	docker cp k8s-ubuntu1804:/packages/archives/. build/ubuntu-18.04/packages/k8s/
	docker rm k8s-ubuntu1804

build/rhel-7/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t kurl/rhel-7-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-rhel7/Dockerfile \
		bundles/k8s-rhel7
	-docker rm -f k8s-rhel7 2>/dev/null
	docker create --name k8s-rhel7 kurl/rhel-7-k8s:${KUBERNETES_VERSION}
	mkdir -p build/rhel-7/packages/k8s
	docker cp k8s-rhel7:/packages/archives/. build/rhel-7/packages/k8s/
	docker rm k8s-rhel7

tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst: deps
	mkdir -p tmp/kubernetes
	# CircleCI GOPATH is two paths separated by :
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/pkg ./tmp/kubernetes/
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/.git ./tmp/kubernetes/
	rm tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst
	KUBERNETES_VERSION=${KUBERNETES_VERSION} PAUSE_VERSION=${PAUSE_VERSION} ETCD_VERSION=${ETCD_VERSION} COREDNS_VERSION=${COREDNS_VERSION} WEAVE_VERSION=${WEAVE_VERSION} ROOK_VERSION=${ROOK_VERSION} CEPH_VERSION=${CEPH_VERSION} CONTOUR_VERSION=${CONTOUR_VERSION} ENVOY_VERSION=${ENVOY_VERSION} ./bundles/k8s-containers/mk-image-cache-lst common > tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst

build/k8s-images.tar: tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst
	mkdir -p build
	$(eval k8s_images_image = $(shell linuxkit pkg build ./tmp/kubernetes/pkg/kubernetes-docker-image-cache-common | grep 'Tagging linuxkit/kubernetes-docker-image-cache' | awk '{print $$2}'))
	docker tag ${k8s_images_image} kurl/k8s-images:${KUBERNETES_VERSION}
	docker save kurl/k8s-images:${KUBERNETES_VERSION} > build/k8s-images.tar

dist: dist/airgap.tar.gz dist/k8s-ubuntu-1604.tar.gz dist/k8s-ubuntu-1804.tar.gz dist/k8s-rhel-7.tar.gz dist/yaml dist/install.sh dist/join.sh

dist/airgap.tar.gz:
	mkdir -p dist
	tar cf dist/airgap.tar -C build .
	gzip dist/airgap.tar

dist/k8s-ubuntu-1604.tar.gz: build/ubuntu-16.04/packages/k8s
	mkdir -p dist
	tar cf dist/k8s-ubuntu-1604.tar -C build/ubuntu-16.04/packages/k8s .
	gzip dist/k8s-ubuntu-1604.tar

dist/k8s-ubuntu-1804.tar.gz: build/ubuntu-18.04/packages/k8s
	mkdir -p dist
	tar cf dist/k8s-ubuntu-1804.tar -C build/ubuntu-18.04/packages/k8s .
	gzip dist/k8s-ubuntu-1804.tar

dist/k8s-rhel-7.tar.gz: build/rhel-7/packages/k8s
	mkdir -p dist
	tar cf dist/k8s-rhel-7.tar -C build/rhel-7/packages/k8s .
	gzip dist/k8s-rhel-7.tar

dist/yaml:
	mkdir -p dist
	cp -r yaml dist/

dist/install.sh: build/install.sh
	mkdir -p dist
	cp build/install.sh dist/

dist/join.sh: build/join.sh
	mkdir -p dist
	cp build/join.sh dist/

staging:
	$(MAKE) -C web deps build
	sed -i.bak 's/INSTALL_URL=.*/INSTALL_URL=https:\/\/staging.kurl.sh/' "dist/install.sh" && rm dist/install.sh.bak
	cp dist/install.sh dist/latest
	cp dist/install.sh dist/unstable

prod:
	$(MAKE) -C web deps build
	sed -i.bak 's/INSTALL_URL=.*/INSTALL_URL=https:\/\/kurl.sh/' "dist/install.sh" && rm dist/install.sh.bak
	cp dist/install.sh dist/latest
	cp dist/install.sh dist/unstable

watchrsync:
	rsync -r build/ubuntu-18.04 ${USER}@${HOST}:kurl
	bin/watchrsync.js
