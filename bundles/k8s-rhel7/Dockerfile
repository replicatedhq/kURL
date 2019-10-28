FROM centos:7
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives
RUN yumdownloader --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubeadm-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	kubernetes-cni

# First upgrade step requires upgraded kubeadm binary before kubeadm package is upgraded
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
RUN curl -sSL https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubeadm > /packages/archives/kubeadm

RUN curl -sSL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v3.3.0/kustomize_v3.3.0_linux_amd64.tar.gz > /packages/archives/kustomize.tar.gz && tar -C /packages/archives/ -xzf /packages/archives/kustomize.tar.gz

CMD cp -r /packages/archives/* /out/
