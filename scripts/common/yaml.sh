
function render_yaml() {
    if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
        mkdir -p $YAML_DIR
        curl $INSTALL_URL/dist/yaml/$1 > $YAML_DIR/$1
    fi
	eval "echo \"$(cat $YAML_DIR/$1)\""
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

    sed '/patchesStrategicMerge.*/a "- $patch_file"' "$kustomization_file"
}
