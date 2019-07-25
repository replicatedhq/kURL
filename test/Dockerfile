FROM ubuntu:18.04

RUN apt update && apt install -y \
	curl \
	keychain

RUN curl -fsS https://releases.hashicorp.com/terraform/0.12.5/terraform_0.12.5_linux_amd64.zip | gunzip >terraform && chmod +x terraform && mv terraform /usr/local/bin

COPY test/ /test
COPY scripts/ /scripts
COPY yaml/ /yaml

RUN cd /test/gcp && terraform init

WORKDIR /test/bin
