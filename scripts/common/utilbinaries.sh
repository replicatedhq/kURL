function download_util_binaries() {
    curl -Ss -L $KURL_UTIL_BINARIES -o /tmp/kurl_util.tgz
    tar zxf /tmp/kurl_util.tgz -C /tmp

    BIN_YAMLUTIL=/tmp/kurl_util/bin/yamlutil
    BIN_DOCKER_CONFIG=/tmp/kurl_util/bin/docker-config
    BIN_SUBNET=/tmp/kurl_util/bin/subnet
}