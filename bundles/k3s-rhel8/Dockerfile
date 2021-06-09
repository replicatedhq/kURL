# THIS ONLY DOWNLOADS THE SELINUX POLICY, not the k3s cli
FROM centos:8

RUN yum install -y gettext # envsubst
RUN yum install -y yum-utils # yumdownloader
RUN yum install -y createrepo

RUN mkdir -p /packages/archives

ADD ./rancher-k3s-common.repo.tmpl /tmp/

ENV rpm_site=rpm.rancher.io
ENV k3s_rpm_channel=stable
ENV maj_ver=8

ARG K3S_VERSION

RUN envsubst < /tmp/rancher-k3s-common.repo.tmpl > /etc/yum.repos.d/rancher-k3s-common.repo
RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    k3s-selinux
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
