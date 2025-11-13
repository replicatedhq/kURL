# Upstream Dockerfile: https://github.com/minio/minio/blob/master/Dockerfile.release
# Go build flags: https://github.com/minio/minio/blob/master/Makefile

FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder

ARG TARGETARCH
ARG RELEASE

ENV GOPATH=/go
ENV CGO_ENABLED=0

# Build MinIO binary
WORKDIR /build

RUN apk add -U --no-cache ca-certificates git && \
    git clone https://github.com/minio/minio/ . && \
    git checkout ${RELEASE}

RUN go build -tags kqueue -trimpath --ldflags "-s -w \
    -X github.com/minio/minio/cmd.ReleaseTag=${RELEASE}" -o ./minio

FROM registry.access.redhat.com/ubi9/ubi-micro:latest

COPY --from=builder /build/minio* /usr/bin/
COPY --from=builder /build/CREDITS /licenses/CREDITS
COPY --from=builder /build/LICENSE /licenses/LICENSE
COPY --from=builder /build/NOTICE /licenses/NOTICE
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

RUN chmod +x /usr/bin/minio

EXPOSE 9000

VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/minio"]
