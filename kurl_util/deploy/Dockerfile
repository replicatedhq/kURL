FROM golang:1.26 AS build

WORKDIR /go/src/github.com/replicatedhq/kurl
COPY kurl_util/cmd kurl_util/cmd
COPY kurl_util/Makefile kurl_util/Makefile
COPY pkg pkg
COPY cmd cmd
COPY go.mod go.mod
COPY go.sum go.sum
COPY Makefile Makefile

RUN make build/bin

FROM golang:1.27.1 AS cri-tools-build

ARG CRITOOLS_VERSION=v1.37.0
ARG CRITOOLS_COMMIT=13496db06e3f6636a0855977dd86344698dfc501

RUN git clone --depth 1 --branch "$CRITOOLS_VERSION" https://github.com/kubernetes-sigs/cri-tools.git /src \
  && test "$(git -C /src rev-parse HEAD)" = "$CRITOOLS_COMMIT"

WORKDIR /src

# The upstream release still includes vulnerable x/mod. Rebuild both tools with
# the fixed dependency rather than copying its precompiled release binaries.
# x/mod v0.40.0 requires x/tools v0.49.0, so go get also bumps x/tools from
# v0.48.0. Flags mirror upstream hack/release.sh (CGO_ENABLED=0, -trimpath,
# Version ldflag with the "v" prefix). -mod=mod is required because the vendor
# directory no longer matches the modified go.mod.
RUN go get golang.org/x/mod@v0.40.0 \
  && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=mod -trimpath \
    -ldflags "-X sigs.k8s.io/cri-tools/pkg/version.Version=${CRITOOLS_VERSION}" \
    -o /crictl ./cmd/crictl \
  && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go test -mod=mod -trimpath -c \
    -ldflags "-X sigs.k8s.io/cri-tools/pkg/version.Version=${CRITOOLS_VERSION}" \
    -o /critest ./cmd/critest

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN . /etc/os-release; apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    libzstd1 \
    \
    ca-certificates \
    curl \
    gnupg2 \
    ipvsadm \
    netcat-openbsd \
    openssl \
    rsync \
    strace \
    sysstat \
    tcpdump \
    telnet \
  && rm -rf /var/lib/apt/lists/*

COPY --from=cri-tools-build /crictl /critest /usr/local/bin/

COPY --from=build /go/src/github.com/replicatedhq/kurl/build/bin/* /usr/local/bin/

ARG COMMIT=unknown
ENV COMMIT=$COMMIT

# This image is used as an initContainer in the velero deployment to register the  restore plugin
ENTRYPOINT ["/bin/bash", "-c", "cp /usr/local/bin/veleroplugin /target/kotsadmrestore"]
