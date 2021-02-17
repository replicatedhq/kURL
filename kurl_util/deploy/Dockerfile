FROM golang:1.13-buster AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY kurlkinds kurlkinds
COPY kurl_util kurl_util
COPY go.mod go.mod

RUN make -C kurl_util build

FROM debian:buster-slim

COPY --from=build /go/src/github.com/replicatedhq/kurl/kurl_util/bin/* /usr/local/bin/

ARG commit=unknown
ENV COMMIT=$commit
