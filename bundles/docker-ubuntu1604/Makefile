DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v18.09.7-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v18.09.7-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:ubuntu-1604-v18.09.7-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v18.09.7-${DATE} > image.tar
	tar xvf image.tar -C image
	tar xvf image/4a1310ab9161b8600d6f887fbc8947ca7652aa84106dfc3c41ad648f0a941165/layer.tar
