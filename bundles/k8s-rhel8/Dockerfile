FROM centos:8
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yum install yum-utils -y
RUN yumdownloader --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubeadm-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	kubernetes-cni \
	git

# First upgrade step requires upgraded kubeadm binary before kubeadm package is upgraded
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
RUN curl -sSL https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubeadm > /packages/archives/kubeadm
