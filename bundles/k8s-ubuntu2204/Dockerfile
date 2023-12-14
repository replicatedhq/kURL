FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install curl apt-transport-https gnupg tzdata ca-certificates

RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

ARG KUBERNETES_MINOR_VERSION

RUN echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update

RUN apt-get update
RUN mkdir -p /packages/archives

ARG KUBERNETES_VERSION
RUN apt-get install -d -y tzdata \
	kubelet=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) \
	kubectl=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) \
	git \
	-oDebug::NoLocking=1 -o=dir::cache=/packages/

CMD cp -r /packages/archives/* /out/
