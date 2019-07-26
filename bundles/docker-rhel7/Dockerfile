FROM centos:7
ARG DOCKER_VERSION

RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
RUN mkdir -p /packages/archives
RUN yumdownloader --resolve --destdir=/packages/archives -y docker-ce-$(yum list --showduplicates 'docker-ce' | grep 18.09.8 | tail -1 | awk '{ print $2 }' | sed 's/.\://')

CMD cp -r /packages/archives/* /out/
