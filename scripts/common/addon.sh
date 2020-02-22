
function addon() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    logStep "Addon $name $version"

    rm -rf $DIR/kustomize/$name
    mkdir -p $DIR/kustomize/$name

    . $DIR/addons/$name/$version/install.sh

    $name
}

function addon_pre_init() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    addon_load "$name" "$version"

    . $DIR/addons/$name/$version/install.sh

    if commandExists ${name}_pre_init; then
        ${name}_pre_init
    fi
}

function addon_join() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    addon_load "$name" "$version"

    . $DIR/addons/$name/$version/install.sh

    if commandExists ${name}_join; then
        ${name}_join
    fi
}

function addon_load() {
    local name=$1
    local version=$2

    if [ -z "$version" ]; then
        return 0
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        curl -sSLO "$KURL_URL/dist/$name-$version.tar.gz"
        tar xf $name-$version.tar.gz
        rm $name-$version.tar.gz
    fi

    load_images $DIR/addons/$name/$version/images
}

function addon_outro() {
    while read -r name; do
        if commandExists ${name}_outro; then
            ${name}_outro
        fi
    done < <(find addons/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}
