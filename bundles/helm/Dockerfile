FROM ubuntu:18.04
RUN apt-get update && apt-get -y install curl

RUN mkdir -p /helm
WORKDIR /helm


RUN curl -fsSLO "https://get.helm.sh/helm-v3.5.1-linux-amd64.tar.gz" && \
	tar zxvf helm-v3.5.1-linux-amd64.tar.gz && \
	mv linux-amd64/helm ./helm && \
	rm -rf ./linux-amd64 && \
	rm helm-*

RUN curl -fsSLO "https://github.com/roboll/helmfile/releases/download/v0.138.2/helmfile_linux_amd64" && \
	mv helmfile_linux_amd64 helmfile && \
	chmod +x helmfile
