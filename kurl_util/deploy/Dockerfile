FROM golang:1.13-buster AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY Makefile Makefile
COPY go.mod go.mod
COPY go.sum go.sum
COPY cmd cmd

RUN make build

FROM debian:buster-slim

COPY --from=build /go/src/github.com/replicatedhq/kurl/bin/* /usr/local/bin/

ARG commit=unknown
ENV COMMIT=$commit
