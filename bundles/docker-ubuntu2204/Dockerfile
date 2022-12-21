# This image builds the an ubuntu image with the docker version informed.
# More info: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
# Update the apt package index and install packages to allow apt to use a repository over HTTPS:
RUN apt-get -y update && \
    apt-get -y install \
        ca-certificates \
        curl \
        gnupg \
        lsb-release tzdata

# Add Docker’s official GPG key:
RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Use the following command to set up the repository:
RUN echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# To create directory to export the image to build/packages/docker/${DOCKER_VERSION}/ubuntu-<version>
# See the build.sh script
RUN mkdir -p /packages/archives

# Update to be able to get the right pkg with apt-cache madison docker-ce-cli and docker-ce
# in order to install the specific docker version informed via ARG
RUN apt-get -y update

# DOCKER_VERSION stores the value informed to via arg to build the image.
# **Note**: You can test it out with docker build --build-arg DOCKER_VERSION=20.10.17 .
ARG DOCKER_VERSION

# Installs spefic docker version informed via the ARG DOCKER_VERSION
RUN apt-get -d -y install --no-install-recommends tzdata \
      docker-ce-cli=$(apt-cache madison docker-ce-cli | grep ${DOCKER_VERSION} | head -1 | awk '{$1=$1};1' | cut -d' ' -f 3) \
      docker-ce=$(apt-cache madison docker-ce | grep ${DOCKER_VERSION} | head -1 | awk '{$1=$1};1' | cut -d' ' -f 3) \
      -oDebug::NoLocking=1 -o=dir::cache=/packages/

CMD cp -r /packages/archives/* /out/
