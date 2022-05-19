FROM centos:7
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yumdownloader --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	kubernetes-cni \
	git

CMD cp -r /packages/archives/* /out/
