
function get_yaml() {
    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        curl -sSOL $KURL_URL/dist/common.tar.gz 
        tar xf common.tar.gz
        rm common.tar.gz
    fi
}

function render_yaml() {
	eval "echo \"$(cat $DIR/yaml/$1)\""
}

function render_yaml_file() {
	eval "echo \"$(cat $1)\""
}

function insert_patches_strategic_merge() {
    local kustomization_file="$1"
    local patch_file="$2"

    if ! grep -q "patchesStrategicMerge" "$kustomization_file"; then
        echo "patchesStrategicMerge:" >> "$kustomization_file"
    fi

    sed -i "/patchesStrategicMerge.*/a - $patch_file" "$kustomization_file"
}

function insert_resources() {
    local kustomization_file="$1"
    local resource_file="$2"

    if ! grep -q "resources" "$kustomization_file"; then
        echo "resources:" >> "$kustomization_file"
    fi

    sed -i "/resources.*/a - $resource_file" "$kustomization_file"
}
