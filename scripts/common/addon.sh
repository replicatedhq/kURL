
function addon() {
    local name=$1
    local version=$2

    logStep "Addon $name $version"

    rm -rf $DIR/kustomize/$name
    mkdir -p $DIR/kustomize/$name

    if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
        curl -O "$INSTALL_URL/dist/addons/$name-$version.tar.gz"
        mkdir -p $DIR/addons/$name/$version
        tar xf $name-$version.tar.gz -C $DIR/addons/$name/$version
    fi

    . $DIR/addons/$name/$version/install.sh

    $name
}
