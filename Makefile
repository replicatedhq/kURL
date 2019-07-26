DOCKER_VERSION=18.09.8
KUBERNETES_VERSION=1.15.1

clean:
	rm -rf build tmp

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :

build: build/ubuntu-16.04/packages/k8s

build/ubuntu-16.04: build/ubuntu-16.04/packages/docker

build/ubuntu-18.04: build/ubuntu-18.04/packages/docker

build/ubuntu-16.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t aka/ubuntu-1604-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1604/Dockerfile \
		bundles/docker-ubuntu1604
	docker run --rm \
		-v ${PWD}/build/ubuntu-16.04/packages/docker:/out \
		aka/ubuntu-1604-docker:${DOCKER_VERSION}

build/ubuntu-18.04/packages/docker:
	docker build \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		-t aka/ubuntu-1804-docker:${DOCKER_VERSION} \
		-f bundles/docker-ubuntu1804/Dockerfile \
		bundles/docker-ubuntu1804
	docker run --rm \
		-v ${PWD}/build/ubuntu-18.04/packages/docker:/out \
		aka/ubuntu-1804-docker:${DOCKER_VERSION}

build/ubuntu-16.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t aka/ubuntu-1604-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1604/Dockerfile \
		bundles/k8s-ubuntu1604
	docker run --rm \
		-v ${PWD}/build/ubuntu-16.04/packages/k8s:/out \
		aka/ubuntu-1604-k8s:${KUBERNETES_VERSION}

build/ubuntu-18.04/packages/k8s:
	docker build \
		--build-arg KUBERNETES_VERSION=${KUBERNETES_VERSION} \
		-t aka/ubuntu-1804-k8s:${KUBERNETES_VERSION} \
		-f bundles/k8s-ubuntu1804/Dockerfile \
		bundles/k8s-ubuntu1804
	docker run --rm \
		-v ${PWD}/build/ubuntu-18.04/packages/k8s:/out \
		aka/ubuntu-1804-k8s:${KUBERNETES_VERSION}

tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst:
	mkdir -p tmp/kubernetes
	# CircleCI GOPATH is two paths separated by :
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/pkg ./tmp/kubernetes/
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/.git ./tmp/kubernetes/
	rm tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst
	./bundles/k8s-containers/mk-image-cache-lst common > tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst

build/k8s-images.tar: tmp/kubernetes/pkg/kubernetes-docker-image-cache-common/images.lst
	$(eval k8s_images_image = $(shell linuxkit pkg build ./tmp/kubernetes/pkg/kubernetes-docker-image-cache-common | grep 'Tagging linuxkit/kubernetes-docker-image-cache' | awk '{print $$2}'))
	echo ${k8s_images_image}
	docker tag ${k8s_images_image} quay.io/replicated/k8s-images
	docker save quay.io/replicated/k8s-images > build/k8s-images.tar
