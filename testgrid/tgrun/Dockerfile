############################
FROM golang:1.17-alpine AS builder

RUN apk update && apk add --no-cache git ca-certificates && update-ca-certificates

ADD go.* /go/src/github.com/replicatedhq/kurl/
ADD pkg /go/src/github.com/replicatedhq/kurl/pkg
ADD kurlkinds /go/src/github.com/replicatedhq/kurl/kurlkinds
ADD testgrid/tgapi /go/src/github.com/replicatedhq/kurl/testgrid/tgapi
ADD testgrid/tgrun /go/src/github.com/replicatedhq/kurl/testgrid/tgrun

WORKDIR /go/src/github.com/replicatedhq/kurl/testgrid/tgrun

RUN go mod download
RUN go mod verify

ARG gitsha=unknown
ENV GIT_SHA=$gitsha

ARG buildtime=unknown
ENV BUILD_TIME=$buildtime

RUN CGO_ENABLED=0 go build -o /go/bin/tgrun \
    -ldflags "-X github.com/replicatedhq/kurl/testgrid/tgrun/pkg/version.gitSHA=${GIT_SHA} -X github.com/replicatedhq/kurl/testgrid/tgrun/pkg/version.buildTime=${BUILD_TIME}" \
    ./cmd/run

############################
FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /go/bin/tgrun /bin/tgrun

ENTRYPOINT ["/bin/tgrun"]
