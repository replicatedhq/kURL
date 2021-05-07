FROM ubuntu:16.04
ARG KUBERNETES_VERSION
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install curl apt-transport-https
RUN  curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
COPY ./kubernetes.list /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update

RUN mkdir -p /packages
RUN apt-get install -d -y \
	kubelet=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) \
	kubectl=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) \
	kubernetes-cni \
	git \	
	-oDebug::NoLocking=1 -o=dir::cache=/packages/

