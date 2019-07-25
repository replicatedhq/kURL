DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:rhel7-v18.09.7-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:rhel7-v18.09.7-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:rhel7-v18.09.7-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

export: build
	docker save replicated/docker-packages:rhel7-v18.09.7-${DATE} > packages-docker-rhel7.tar

# this gets run by airgap install script
unpack_example: export
	rm -rf image/
	mkdir -p image/
	tar xvf packages-docker-rhel7.tar -C image
	tar xvf image/d4eb0648b66a267b1ccf96beb1f32a424127bebd770787786604f9ed3fcfc06e/layer.tar
