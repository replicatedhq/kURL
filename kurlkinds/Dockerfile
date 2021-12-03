# Build the manager binary
FROM golang:1.17 AS builder

# Copy in the go src
WORKDIR /go/src/github.com/replicatedhq/kurl/kurlkinds
COPY pkg/    pkg/
COPY cmd/    cmd/
COPY vendor/ vendor/

# Build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o manager github.com/replicatedhq/kurl/kurlkinds/cmd/manager

# Copy the controller-manager into a thin image
FROM ubuntu:latest
WORKDIR /
COPY --from=builder /go/src/github.com/replicatedhq/kurl/kurlkinds/manager .
ENTRYPOINT ["/manager"]
