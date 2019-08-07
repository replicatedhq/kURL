
function addon() {
    local name=$1
    local version=$2

    rm -rf $DIR/kustomize/$name
    mkdir -p $DIR/kustomize/$name

    $name
}
