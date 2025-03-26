FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -y install curl tzdata

RUN mkdir -p /helm
WORKDIR /helm


RUN curl -fsSLO "https://get.helm.sh/helm-v3.15.3-linux-amd64.tar.gz" && \
	tar zxvf helm-v3.15.3-linux-amd64.tar.gz && \
	mv linux-amd64/helm ./helm && \
	rm -rf ./linux-amd64 && \
	rm helm-*

RUN curl -fsSLO "https://github.com/helmfile/helmfile/releases/download/v0.171.0/helmfile_0.171.0_linux_amd64.tar.gz" && \
    tar zxvf helmfile_0.167.0_linux_amd64.tar.gz && \
	chmod +x helmfile
