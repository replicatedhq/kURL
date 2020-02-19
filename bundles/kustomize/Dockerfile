FROM ubuntu:18.04
ENV KUSTOMIZE_VERSION 3.5.3

RUN apt-get update
RUN apt-get -y install curl apt-transport-https gnupg git

RUN mkdir -p /kustomize
WORKDIR /kustomize
RUN curl -fsSLO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz
RUN mv kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz kustomize.tar.gz
