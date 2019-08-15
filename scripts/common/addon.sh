
function addon() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    logStep "Addon $name $version"

    rm -rf $DIR/kustomize/$name
    mkdir -p $DIR/kustomize/$name

    if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
        curl -O "$INSTALL_URL/dist/addons/$name-$version.tar.gz"
        mkdir -p $DIR/addons/$name/$version
        tar xf $name-$version.tar.gz -C $DIR/addons/$name/$version
        rm $name-$version.tar.gz
    fi

    . $DIR/addons/$name/$version/install.sh

    $name
}
