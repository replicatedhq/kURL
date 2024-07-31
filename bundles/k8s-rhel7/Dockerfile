FROM centos:7
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
ARG KUBERNETES_MINOR_VERSION
RUN sed -i "s/__KUBERNETES_MINOR_VERSION__/v${KUBERNETES_MINOR_VERSION}/g" /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yum-config-manager --disable main --disable base --disable extras --disable updates
RUN yum-config-manager --add-repo https://archive.kernel.org/centos-vault/7.9.2009/os/x86_64/
RUN curl https://archive.kernel.org/centos-vault/7.9.2009/os/x86_64/RPM-GPG-KEY-CentOS-7 > vault.gpg.key
RUN rpm --import vault.gpg.key

RUN yum install -y createrepo
RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	git
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
