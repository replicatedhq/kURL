FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -y install curl tzdata

RUN mkdir -p /helm
WORKDIR /helm


RUN curl -fsSLO "https://get.helm.sh/helm-v3.18.4-linux-amd64.tar.gz" && \
	tar zxvf helm-v3.18.4-linux-amd64.tar.gz && \
	mv linux-amd64/helm ./helm && \
	rm -rf ./linux-amd64 && \
	rm helm-*

RUN curl -fsSLO "https://github.com/helmfile/helmfile/releases/download/v1.1.2/helmfile_1.1.2_linux_amd64.tar.gz" && \
    tar zxvf helmfile_1.1.2_linux_amd64.tar.gz && \
	chmod +x helmfile
