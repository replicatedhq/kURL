FROM centos:7
ARG CONTAINERD_VERSION

RUN yum install -y createrepo
RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
RUN mkdir -p /packages/archives
RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    containerd.io-$(yum list --showduplicates 'containerd.io' | grep ${CONTAINERD_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://')
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
