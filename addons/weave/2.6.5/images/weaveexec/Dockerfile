# https://github.com/weaveworks/weave/blob/v2.6.5/prog/weaver/Dockerfile.template
# https://github.com/weaveworks/weave/blob/v2.6.5/prog/weaveexec/Dockerfile.template

FROM weaveworks/weaveexec:2.6.5 AS base

FROM alpine:3.13

RUN apk add --update \
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
