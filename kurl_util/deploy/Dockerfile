FROM golang:1.16-buster AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY kurlkinds kurlkinds
COPY kurl_util kurl_util
COPY pkg pkg
COPY cmd cmd
COPY go.mod go.mod
COPY go.sum go.sum
COPY Makefile Makefile

RUN make build/bin

FROM debian:buster-slim

RUN DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y --no-install-recommends \
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
    \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /go/src/github.com/replicatedhq/kurl/build/bin/* /usr/local/bin/

ARG commit=unknown
ENV COMMIT=$commit
