FROM centos:7
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
ARG KUBERNETES_MINOR_VERSION
RUN sed -i "s/__KUBERNETES_MINOR_VERSION__/v${KUBERNETES_MINOR_VERSION}/g" /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yum install -y createrepo
RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	git
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
