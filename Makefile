DOCKER_VERSION=18.09.8
KUBERNETES_VERSION=1.15.1

clean:
	rm -rf build

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
