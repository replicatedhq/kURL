# https://github.com/weaveworks/weave/blob/v2.6.5/prog/weave-npc/Dockerfile.template

FROM weaveworks/weave-npc:2.6.5 AS base

FROM alpine:3.13

RUN apk add --update \
    iptables \
    ipset \
    ulogd \
  && rm -rf /var/cache/apk/* \
  && mknod /var/log/ulogd.pcap p

COPY --from=base /usr/bin/weave-npc /usr/bin/weave-npc
COPY --from=base /etc/ulogd.conf /etc/ulogd.conf
COPY --from=base /usr/bin/launch.sh /usr/bin/launch.sh

ENTRYPOINT ["/usr/bin/launch.sh"]
