# https://github.com/weaveworks/weave/blob/v2.8.1/prog/weaver/Dockerfile.template
# https://github.com/weaveworks/weave/blob/v2.8.1/prog/weaveexec/Dockerfile.template

FROM weaveworks/weaveexec:2.8.1 AS base

FROM alpine:3.16

RUN apk add --update --upgrade \
    curl \
    iptables \
    ipset \
    iproute2 \
    conntrack-tools \
    bind-tools \
    ca-certificates \
  && rm -rf /var/cache/apk/*

ENTRYPOINT ["/home/weave/sigproxy", "/home/weave/weave"]

COPY --from=base /home/weave /home/weave
COPY --from=base /usr/bin/weaveutil /usr/bin/weaveutil
COPY --from=base /weavedb /weavedb
COPY --from=base /w /w
COPY --from=base /w-noop /w-noop
COPY --from=base /w-nomcast /w-nomcast
WORKDIR /home/weave