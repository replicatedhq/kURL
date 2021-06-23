FROM centos:7

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
RUN source /tmp/env; yumdownloader --resolve --destdir=/packages/archives -y \
    rke2-server-${rke2_rpm_version} \
    rke2-agent-${rke2_rpm_version}

CMD cp -r /packages/archives/* /out/
