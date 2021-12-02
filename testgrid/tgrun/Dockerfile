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

RUN CGO_ENABLED=0 go build -o /go/bin/tgrun ./cmd/run

############################
FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /go/bin/tgrun /bin/tgrun

ENTRYPOINT ["/bin/tgrun"]
