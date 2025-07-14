FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -y install curl tzdata

RUN mkdir -p /helm
WORKDIR /helm

ARG HELM_VERSION
RUN curl -fsSLO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" && \
	tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz && \
	mv linux-amd64/helm ./helm && \
	rm -rf ./linux-amd64 && \
	rm helm-*

ARG HELMFILE_VERSION
RUN curl -fsSLO "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" && \
    tar zxvf helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz && \
	chmod +x helmfile
