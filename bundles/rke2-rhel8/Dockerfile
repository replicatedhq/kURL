FROM rockylinux:8

RUN echo -e "fastestmirror=1\nmax_parallel_downloads=8" >> /etc/dnf/dnf.conf

RUN yum install -y gettext # envsubst
RUN yum install -y yum-utils # yumdownloader
RUN yum install -y createrepo

RUN yum install -y modulemd-tools

RUN mkdir -p /packages/archives

ADD ./rancher-rke2.repo.tmpl /tmp/

ENV rpm_site=rpm.rancher.io
ENV rke2_rpm_channel=stable
ENV maj_ver=8

ARG RKE2_VERSION

RUN echo "export rke2_majmin=$(echo "${RKE2_VERSION}" | sed -E -e 's/^v([0-9]+\.[0-9]+).*/\1/')" >> /tmp/env
RUN echo "rke2_rpm_version=$(echo "${RKE2_VERSION}" | sed -E -e "s/[\+-]/~/g" | sed -E -e "s/v(.*)/\1/")" >> /tmp/env

RUN source /tmp/env; envsubst < /tmp/rancher-rke2.repo.tmpl > /etc/yum.repos.d/rancher-rke2.repo
RUN source /tmp/env; yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    rke2-server-${rke2_rpm_version} \
    rke2-agent-${rke2_rpm_version}
RUN createrepo_c /packages/archives
RUN repo2module --module-name=kurl.local --module-stream=stable /packages/archives /tmp/modules.yaml
RUN modifyrepo_c --mdtype=modules /tmp/modules.yaml /packages/archives/repodata

CMD cp -r /packages/archives/* /out/
