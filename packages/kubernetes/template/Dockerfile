FROM ubuntu:18.04
RUN apt-get update && apt-get -y install curl apt-transport-https gnupg
RUN  curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
RUN echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
