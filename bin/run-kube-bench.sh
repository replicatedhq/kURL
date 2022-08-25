#!/bin/bash

# ####################################################
# ./run-kube-bench.sh [VERSION]
# if no VERSION argument specified, it will use latest
# E.g. ./run-kube-bench.sh 0.6.8
# ####################################################

USER_VERSION=$1
KUBE_BENCH_VERSION=

if [[ -z $USER_VERSION ]]; then
  KUBE_BENCH_VERSION="$(curl -s https://api.github.com/repos/aquasecurity/kube-bench/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')"
else
  KUBE_BENCH_VERSION=$USER_VERSION
fi

echo "Using kube-bench $KUBE_BENCH_VERSION"

PLATFORM=
case "$(uname -s)" in
  Linux)
    PLATFORM=linux
    ;;

  *)
    echo "Unsupported operating system"
    return 1
    ;;
esac


ARCH=
case "$(uname -m)" in
  x86_64)
    ARCH=amd64
    ;;

  arm64)
    ARCH=arm64
    ;;

  *)
    echo "Unsupported architecture"
    return 1
    ;;
esac

function horizontal_rule {
  printf "%$(tput cols)s\n"|tr " " "-"
}

# download kube-bench binary
curl -fsSL https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_${PLATFORM}_${ARCH}.tar.gz | tar -xz
echo "kube-bench v$KUBE_BENCH_VERSION test starting"
horizontal_rule

./kube-bench --config-dir="$(pwd)"/cfg --config="$(pwd)"/cfg/config.yaml --exit-code=1

horizontal_rule
echo "kube-bench v$KUBE_BENCH_VERSION test finished"
