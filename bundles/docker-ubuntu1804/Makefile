DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1804-v18.09.7-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1804-v18.09.7-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:ubuntu-1804-v18.09.7-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1804-v18.09.7-${DATE} > image.tar
	tar xvf image.tar -C image
	tar xvf image/9d5cc68d81d1df7d52a94abf20f0c31025d1395356ff3cb817a6cce8bc3977bc/layer.tar
