FROM ubuntu:16.04
RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install apt-utils apt-transport-https ca-certificates curl software-properties-common
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
RUN apt-get -y update

RUN mkdir -p /packages/archives
RUN apt-get -d -y install docker-ce=5:18.09.7~3-0~ubuntu-xenial -oDebug::NoLocking=1 -o=dir::cache=/packages/

FROM scratch
COPY --from=0 /packages /
