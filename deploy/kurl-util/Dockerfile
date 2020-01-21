FROM golang:1.13-buster

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY go.mod go.mod
COPY go.sum go.sum
COPY cmd cmd

RUN go build -o proxy cmd/proxy/main.go
RUN go build -o yamlutil cmd/yamlutil/main.go

WORKDIR /go/src/github.com/replicatedhq/kurl/cmd/join
RUN go build -o join main.go

FROM debian:buster-slim

COPY --from=0 /go/src/github.com/replicatedhq/kurl/proxy /usr/local/bin
COPY cmd/proxy/assets /assets

COPY --from=0 /go/src/github.com/replicatedhq/kurl/yamlutil /usr/local/bin

COPY --from=0 /go/src/github.com/replicatedhq/kurl/cmd/join/join /usr/local/bin

ARG commit=unknown
ENV COMMIT=$commit
