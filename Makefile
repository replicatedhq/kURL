.PHONY: clean deps code
SHELL := /bin/bash

include Manifest

clean:
	rm -rf build tmp dist

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :

code: build/Manifest build/scripts build/yaml

build: code build/ubuntu-16.04 build/ubuntu-18.04 build/rhel-7 build/k8s-images.tar

build/ubuntu-16.04: code build/ubuntu-16.04/packages/docker build/ubuntu-16.04/packages/k8s build/k8s-images.tar

build/ubuntu-18.04: code build/ubuntu-18.04/packages/docker build/ubuntu-18.04/packages/k8s build/k8s-images.tar

build/rhel-7: code build/rhel-7/packages/docker build/rhel-7/packages/k8s build/k8s-images.tar

build/ubuntu-16.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t kurl/ubuntu-1604-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1604/Dockerfile \
		bundles/docker-ubuntu1604
	source Manifest && docker run --rm \
		-v ${PWD}/build/ubuntu-16.04/packages/docker:/out \
		kurl/ubuntu-1604-docker:${DOCKER_VERSION}

build/ubuntu-18.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t kurl/ubuntu-1804-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1804/Dockerfile \
		bundles/docker-ubuntu1804
	docker run --rm \
		-v ${PWD}/build/ubuntu-18.04/packages/docker:/out \
		kurl/ubuntu-1804-docker:${DOCKER_VERSION}

build/rhel-7/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t kurl/rhel-7-docker:${DOCKER_VERSION} \
		-f bundles/docker-rhel7/Dockerfile \
		bundles/docker-rhel7
	docker run --rm \
		-v ${PWD}/build/rhel-7/packages/docker:/out \
		kurl/rhel-7-docker:${DOCKER_VERSION} \

build/ubuntu-16.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t kurl/ubuntu-1604-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1604/Dockerfile \
		bundles/k8s-ubuntu1604
	docker run --rm \
		-v ${PWD}/build/ubuntu-16.04/packages/k8s:/out \
		kurl/ubuntu-1604-k8s:${KUBERNETES_VERSION}

build/ubuntu-18.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t kurl/ubuntu-1804-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1804/Dockerfile \
		bundles/k8s-ubuntu1804
	docker run --rm \
		-v ${PWD}/build/ubuntu-18.04/packages/k8s:/out \
		kurl/ubuntu-1804-k8s:${KUBERNETES_VERSION}

build/rhel-7/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t kurl/rhel-7-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-rhel7/Dockerfile \
		bundles/k8s-rhel7
	docker run --rm \
		-v ${PWD}/build/rhel-7/packages/k8s:/out \
		kurl/rhel-7-k8s:${KUBERNETES_VERSION}

tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst:
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

build/Manifest:
	mkdir -p build
	cp Manifest build/

build/scripts:
	mkdir -p build
	cp -r scripts build/

build/yaml:
	mkdir -p build
	cp -r yaml build/

dist/kurl.tar.gz: build
	mkdir -p dist
	tar cf dist/kurl.tar -C build .
	gzip dist/kurl.tar

dist/kurl-ubuntu-1604.tar.gz: build/ubuntu-16.04
	mkdir -p dist
	tar cf dist/kurl-ubuntu-1604.tar -C build .
	gzip dist/kurl-ubuntu-1604.tar -C build .

dist/kurl-ubuntu-1804.tar.gz: build/ubuntu-18.04
	mkdir -p dist
	tar cf dist/kurl-ubuntu-1804.tar -C build .
	gzip dist/kurl-ubuntu-1804.tar

dist/kurl-rhel-7.tar.gz: build/rhel-7
	mkdir -p dist
	tar cf dist/kurl-rhel7.tar -C build .
	gzip dist/kurl-rhel7.tar

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

watchrsync:
	rsync -r build/ubuntu-18.04 ${USER}@${HOST}:kurl
	bin/watchrsync.js
