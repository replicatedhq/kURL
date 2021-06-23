FROM centos:7

RUN yum install -y createrepo
RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
RUN mkdir -p /packages/archives

ARG DOCKER_VERSION

RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
    docker-ce-$(yum list --showduplicates 'docker-ce' | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://') \
    docker-ce-cli-$(yum list --showduplicates 'docker-ce-cli' | grep ${DOCKER_VERSION} | tail -1 | awk '{ print $2 }' | sed 's/.\://')
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
