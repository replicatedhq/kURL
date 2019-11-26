FROM ubuntu:18.04
ARG KUBERNETES_VERSION
RUN apt-get update
RUN apt-get upgrade -y
# git is for krew
RUN apt-get -y install curl apt-transport-https gnupg git
RUN  curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
COPY ./kubernetes.list /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update

RUN mkdir -p /packages/archives
RUN apt-get install -d -y \
	kubeadm=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }') \
	kubelet=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }') \
	kubectl=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }') \
	kubernetes-cni \
	-oDebug::NoLocking=1 -o=dir::cache=/packages/

# this krew installation is used for all linux systems
RUN apt install kubectl=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION} | awk '{ print $3 }')
RUN mkdir -p /krew-install && \
	cd /krew-install && \
	curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/v0.3.2/krew.{tar.gz,yaml}" && \
	tar zxvf krew.tar.gz && \
	./krew-linux_amd64 install --manifest=krew.yaml --archive=krew.tar.gz
ENV PATH=/root/.krew/bin:$PATH

RUN kubectl krew install outdated
RUN kubectl krew install preflight
RUN kubectl krew install support-bundle


# First upgrade step requires upgraded kubeadm binary before kubeadm package is upgraded
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
RUN curl -sSL https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubeadm > /packages/archives/kubeadm
