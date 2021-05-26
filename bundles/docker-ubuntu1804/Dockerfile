FROM ubuntu:18.04
RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install apt-utils apt-transport-https ca-certificates curl software-properties-common
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt-get -y update

RUN mkdir -p /packages/archives

ARG DOCKER_VERSION
RUN apt-get -d -y install --no-install-recommends \
  docker-ce-cli=$(apt-cache madison 'docker-ce-cli' | grep ${DOCKER_VERSION} | head -1 | awk '{$1=$1};1' | cut -d' ' -f 3) \
  docker-ce=$(apt-cache madison 'docker-ce' | grep ${DOCKER_VERSION} | head -1 | awk '{$1=$1};1' | cut -d' ' -f 3) \
  -oDebug::NoLocking=1 -o=dir::cache=/packages/

CMD cp -r /packages/archives/* /out/
