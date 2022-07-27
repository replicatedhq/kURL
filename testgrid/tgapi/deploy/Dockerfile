FROM golang:1.17

ADD go.* /go/src/github.com/replicatedhq/kurl/
ADD pkg /go/src/github.com/replicatedhq/kurl/pkg
ADD kurlkinds /go/src/github.com/replicatedhq/kurl/kurlkinds
ADD testgrid/tgapi /go/src/github.com/replicatedhq/kurl/testgrid/tgapi
ADD testgrid/tgrun /go/src/github.com/replicatedhq/kurl/testgrid/tgrun
WORKDIR /go/src/github.com/replicatedhq/kurl/testgrid/tgapi

ARG gitsha=unknown
ENV GIT_SHA=$gitsha

ARG buildtime=unknown
ENV BUILD_TIME=$buildtime

RUN mkdir -p bin
RUN go build -o ./bin/tgapi \
    -ldflags "-X github.com/replicatedhq/kurl/testgrid/tgapi/pkg/version.gitSHA=${GIT_SHA} -X github.com/replicatedhq/kurl/testgrid/tgapi/pkg/version.buildTime=${BUILD_TIME}" \
    ./cmd/api


FROM debian:stretch-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=0 /go/src/github.com/replicatedhq/kurl/testgrid/tgapi/bin/* /

EXPOSE 3000
