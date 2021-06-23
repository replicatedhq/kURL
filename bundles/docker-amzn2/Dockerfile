FROM amazonlinux:2

RUN yum install -y yum-utils createrepo amazon-linux-extras

RUN mkdir -p /packages/archives

RUN amazon-linux-extras install docker # hack to enable the extras repo
RUN mkdir -p /tmp/empty-directory/etc/yum/vars/
RUN cp -r /etc/yum/vars/* /tmp/empty-directory/etc/yum/vars/

ARG DOCKER_VERSION

RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    docker-$(yum list --showduplicates docker | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://')
RUN createrepo_c /packages/archives

CMD cp -r /packages/archives/* /out/
