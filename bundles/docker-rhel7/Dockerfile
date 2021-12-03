FROM registry.access.redhat.com/ubi7/ubi:7.9 AS builder

RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
RUN mkdir -p /packages/archives

ARG DOCKER_VERSION

RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    docker-ce-$(yum list --showduplicates 'docker-ce' | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://') \
    docker-ce-cli-$(yum list --showduplicates 'docker-ce-cli' | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://')

# installing "createrepo" package on rhel requires a subscription. it's only needed to create the repo,
# and it's not part of the produced packages, so we can do this:
FROM centos:7
COPY --from=builder /packages/archives /packages/archives
RUN yum install -y createrepo
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
