FROM golang:1.20 AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY kurl_util kurl_util
COPY pkg pkg
COPY cmd cmd
COPY go.mod go.mod
COPY go.sum go.sum
COPY Makefile Makefile

RUN make build/bin

FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

RUN . /etc/os-release; apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    libzstd1 \
    \
    ca-certificates \
    curl \
    gnupg2 \
    ipvsadm \
    netcat \
    openssl \
    rsync \
    strace \
    sysstat \
    tcpdump \
    telnet \
  && curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/xUbuntu_${VERSION_ID}/Release.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/devel_kubic_libcontainers_stable.gpg \
  && echo "deb [signed-by=/etc/apt/trusted.gpg.d/devel_kubic_libcontainers_stable.gpg] http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /"| tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list \
  && apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    cri-tools \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /go/src/github.com/replicatedhq/kurl/build/bin/* /usr/local/bin/

ARG commit=unknown
ENV COMMIT=$commit

# This image is used as an initContainer in the velero deployment to register the  restore plugin
ENTRYPOINT ["/bin/bash", "-c", "cp /usr/local/bin/veleroplugin /target/kotsadmrestore"]
