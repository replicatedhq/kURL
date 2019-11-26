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
	kubeadm=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }') \
	kubelet=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }') \
	kubectl=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }') \
	kubernetes-cni \
	-oDebug::NoLocking=1 -o=dir::cache=/packages/

# First upgrade step requires upgraded kubeadm binary before kubeadm package is upgraded
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
RUN curl -sSL https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubeadm > /packages/archives/kubeadm
