FROM ubuntu:16.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install curl apt-transport-https gnupg tzdata

RUN curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://dl.k8s.io/apt/doc/apt-key.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] http://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
RUN mkdir -p /packages/archives

ARG KUBERNETES_VERSION
RUN apt-get install -d -y tzdata \
	kubelet=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) \
	kubectl=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) \
	git \
	-oDebug::NoLocking=1 -o=dir::cache=/packages/

CMD cp -r /packages/archives/* /out/
