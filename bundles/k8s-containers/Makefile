DATE=$(shell date +%Y%m%d)

all: deps update_k8s_manifest build retag push

deps:
	go get github.com/linuxkit/linuxkit/src/cmd/linuxkit
	go get github.com/linuxkit/kubernetes || :

update_k8s_manifest_%: clean deps
	mkdir -p ./kubernetes-tmp-$*
	# CircleCI GOPATH is two paths separated by :
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/pkg ./kubernetes-tmp-$*/
	cp -r $(shell echo ${GOPATH} | cut -d ':' -f 1)/src/github.com/linuxkit/kubernetes/.git ./kubernetes-tmp-$*/
	./mk-image-cache-lst-$* common > ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common/images.lst
	./mk-image-cache-lst-$* control-plane > ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane/images.lst

build_%:
	$(eval common_image = $(shell linuxkit pkg build ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-common 2>/dev/null | grep 'Tagging linuxkit/kubernetes-docker-image-cache-common'| awk '{print $$2}'))
	docker tag ${common_image} quay.io/replicated/k8s-images-common:$*-${DATE}
	$(eval control_image = $(shell linuxkit pkg build ./kubernetes-tmp-$*/pkg/kubernetes-docker-image-cache-control-plane 2>/dev/null | grep 'Tagging linuxkit/kubernetes-docker-image-cache-control-plane' | awk '{print $$2}'))
	docker tag ${control_image} quay.io/replicated/k8s-images-control:$*-${DATE}

push_%:
	docker push quay.io/replicated/k8s-images-common:$*-${DATE}
	docker push quay.io/replicated/k8s-images-control:$*-${DATE}

clean:
	rm -rf ./kubernetes-tmp*
