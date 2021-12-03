# THIS ONLY DOWNLOADS THE SELINUX POLICY, not the k3s cli
FROM registry.access.redhat.com/ubi8/ubi:8.1 AS builder

RUN echo -e "fastestmirror=1\nmax_parallel_downloads=8" >> /etc/dnf/dnf.conf

# envsubst, yumdownloader
RUN yum install -y gettext yum-utils

RUN mkdir -p /packages/archives

ADD ./rancher-k3s-common.repo.tmpl /tmp/

ENV rpm_site=rpm.rancher.io
ENV k3s_rpm_channel=stable
ENV maj_ver=8

ARG K3S_VERSION

RUN envsubst < /tmp/rancher-k3s-common.repo.tmpl > /etc/yum.repos.d/rancher-k3s-common.repo
RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    k3s-selinux

# installing "createrepo" package on rhel requires a subscription. it's only needed to create the repo,
# and it's not part of the produced packages, so we can do this:
FROM centos:8
COPY --from=builder /packages/archives /packages/archives
RUN yum install -y createrepo modulemd-tools
RUN createrepo_c /packages/archives
RUN repo2module --module-name=kurl.local --module-stream=stable /packages/archives /tmp/modules.yaml
RUN modifyrepo_c --mdtype=modules /tmp/modules.yaml /packages/archives/repodata

CMD cp -r /packages/archives/* /out/
