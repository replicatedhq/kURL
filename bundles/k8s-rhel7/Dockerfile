FROM centos:7
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yum install -y createrepo
RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	kubernetes-cni \
	git
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
