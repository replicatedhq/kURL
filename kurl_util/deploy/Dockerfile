FROM golang:1.24 AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY kurl_util/cmd kurl_util/cmd
COPY kurl_util/Makefile kurl_util/Makefile
COPY pkg pkg
COPY cmd cmd
COPY go.mod go.mod
COPY go.sum go.sum
COPY Makefile Makefile

RUN make build/bin

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN . /etc/os-release; apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    libzstd1 \
    \
    ca-certificates \
    curl \
    gnupg2 \
    ipvsadm \
    netcat-openbsd \
    openssl \
    rsync \
    strace \
    sysstat \
    tcpdump \
    telnet \
  && rm -rf /var/lib/apt/lists/*

ARG CRITOOLS_VERSION=v1.34.0

# Install crictl and critest with latest version discovery
RUN curl -sSL -o crictl-linux-amd64.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRITOOLS_VERSION/crictl-$CRITOOLS_VERSION-linux-amd64.tar.gz \
  && tar zxvf crictl-linux-amd64.tar.gz -C /usr/local/bin \
  && rm -f crictl-linux-amd64.tar.gz

RUN curl -sSL -o critest-linux-amd64.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRITOOLS_VERSION/critest-$CRITOOLS_VERSION-linux-amd64.tar.gz \
  && tar zxvf critest-linux-amd64.tar.gz -C /usr/local/bin \
  && rm -f critest-linux-amd64.tar.gz

COPY --from=build /go/src/github.com/replicatedhq/kurl/build/bin/* /usr/local/bin/

ARG COMMIT=unknown
ENV COMMIT=$COMMIT

# This image is used as an initContainer in the velero deployment to register the  restore plugin
ENTRYPOINT ["/bin/bash", "-c", "cp /usr/local/bin/veleroplugin /target/kotsadmrestore"]
