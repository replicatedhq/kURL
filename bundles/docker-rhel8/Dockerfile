FROM registry.access.redhat.com/ubi8/ubi:8.1 AS builder

RUN echo -e "fastestmirror=1\nmax_parallel_downloads=8" >> /etc/dnf/dnf.conf

RUN yum install -y yum-utils
RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
RUN mkdir -p /packages/archives

ARG DOCKER_VERSION

RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    docker-ce-$(yum list --showduplicates 'docker-ce' | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://') \
    docker-ce-cli-$(yum list --showduplicates 'docker-ce-cli' | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://')

# installing "createrepo" package on rhel requires a subscription. it's only needed to create the repo,
# and it's not part of the produced packages, so we can do this:
FROM centos:8.1.1911
COPY --from=builder /packages/archives /packages/archives
RUN yum install -y createrepo modulemd-tools
RUN createrepo_c /packages/archives
RUN repo2module --module-name=kurl.local --module-stream=stable /packages/archives /tmp/modules.yaml
RUN modifyrepo_c --mdtype=modules /tmp/modules.yaml /packages/archives/repodata

CMD cp -r /packages/archives/* /out/
