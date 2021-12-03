FROM registry.access.redhat.com/ubi7/ubi:7.9 AS builder

RUN yum install -y gettext

RUN mkdir -p /packages/archives

ADD ./rancher-rke2.repo.tmpl /tmp/

ENV rpm_site=rpm.rancher.io
ENV rke2_rpm_channel=stable
ENV maj_ver=7

ARG RKE2_VERSION

RUN echo "export rke2_majmin=$(echo "${RKE2_VERSION}" | sed -E -e 's/^v([0-9]+\.[0-9]+).*/\1/')" >> /tmp/env
RUN echo "rke2_rpm_version=$(echo "${RKE2_VERSION}" | sed -E -e "s/[\+-]/~/g" | sed -E -e "s/v(.*)/\1/")" >> /tmp/env

RUN source /tmp/env; envsubst < /tmp/rancher-rke2.repo.tmpl > /etc/yum.repos.d/rancher-rke2.repo
RUN source /tmp/env; yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    rke2-server-${rke2_rpm_version} \
    rke2-agent-${rke2_rpm_version}

# installing "createrepo" package on rhel requires a subscription. it's only needed to create the repo,
# and it's not part of the produced packages, so we can do this:
FROM centos:7
COPY --from=builder /packages/archives /packages/archives
RUN yum install -y createrepo
RUN createrepo /packages/archives
CMD cp -r /packages/archives/* /out/