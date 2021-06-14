# THIS ONLY DOWNLOADS THE SELINUX POLICY, not the k3s cli
FROM centos:7

RUN yum install -y gettext

RUN mkdir -p /packages/archives

ADD ./rancher-k3s-common.repo.tmpl /tmp/

# Adapted from https://get.k3s.io/ install script
ENV rpm_site=rpm.rancher.io
ENV k3s_rpm_channel=stable
ENV maj_ver=7

ARG K3S_VERSION

RUN envsubst < /tmp/rancher-k3s-common.repo.tmpl > /etc/yum.repos.d/rancher-k3s-common.repo
RUN yumdownloader --resolve --destdir=/packages/archives -y \
    k3s-selinux

CMD cp -r /packages/archives/* /out/
