FROM golang:1.14

ADD . /go/src/github.com/replicatedhq/kurl/testgrid/tgapi
WORKDIR /go/src/github.com/replicatedhq/kurl/testgrid/tgapi
RUN make build


FROM debian:stretch-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=0 /go/src/github.com/replicatedhq/kurl/testgrid/tgapi/bin/* /

EXPOSE 3000
