# https://github.com/weaveworks/weave/blob/v2.8.1/prog/weaver/Dockerfile.template
# https://github.com/weaveworks/weave/blob/v2.8.1/prog/weave-kube/Dockerfile.template

FROM weaveworks/weave-kube:2.8.1 AS base

FROM alpine:3.16

RUN apk add --update \
    curl \
    ipset \
    iproute2 \
    conntrack-tools \
    bind-tools \
    ca-certificates \
  && apk add --repository https://dl-cdn.alpinelinux.org/alpine/v3.15/main \
    iptables=1.8.7-r1 \
  && rm -rf /var/cache/apk/*

COPY --from=base /home/weave /home/weave
COPY --from=base /usr/bin/weaveutil /usr/bin/weaveutil
COPY --from=base /weavedb /weavedb

ENTRYPOINT ["/home/weave/launch.sh"]
WORKDIR /home/weave