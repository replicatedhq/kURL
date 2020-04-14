#!/bin/bash

function pkgs() {
    for dir in $(find $1 -mindepth 2 -maxdepth 2 -type d)
    do
        local name=$(echo $dir | awk -F "/" '{print $2 }')
        local version=$(echo $dir | awk -F "/" '{print $3 }')
        echo "${name}-${version}.tar.gz"
    done
}

function list_all_packages() {
    pkgs addons
    pkgs packages
    echo "docker-18.09.8.tar.gz"
    echo "docker-19.03.4.tar.gz"
    echo "common.tar.gz"
    if [ -z "$VERSION_TAG" ]
    then
        echo "kurl-bin-utils-latest.tar.gz"
    else
        echo "kurl-bin-utils-${VERSION_TAG}.tar.gz"
    fi
}

list_all_packages
