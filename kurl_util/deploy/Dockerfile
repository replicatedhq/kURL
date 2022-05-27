FROM golang:1.17-buster AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY kurlkinds kurlkinds
COPY kurl_util kurl_util
COPY pkg pkg
COPY cmd cmd
COPY go.mod go.mod
COPY go.sum go.sum
COPY Makefile Makefile

RUN make build/bin

FROM ubuntu:jammy

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libzstd1 \
    \
    curl \
    ipvsadm \
    netcat \
    openssl \
    strace \
    sysstat \
    tcpdump \
    telnet \
    rsync \
    \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /go/src/github.com/replicatedhq/kurl/build/bin/* /usr/local/bin/

ARG commit=unknown
ENV COMMIT=$commit

# This image is used as an initContainer in the velero deployment to register the  restore plugin
ENTRYPOINT ["/bin/bash", "-c", "cp /usr/local/bin/veleroplugin /target/kotsadmrestore"]
