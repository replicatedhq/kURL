
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

function setup_kubeadm_kustomize() {
    # Clean up the source directories for the kubeadm kustomize resources and
    # patches.
    rm -rf $DIR/kustomize/kubeadm/init
    cp -rf $DIR/kustomize/kubeadm/init-orig $DIR/kustomize/kubeadm/init
    rm -rf $DIR/kustomize/kubeadm/join
    cp -rf $DIR/kustomize/kubeadm/join-orig $DIR/kustomize/kubeadm/join
    rm -rf $DIR/kustomize/kubeadm/init-patches
    mkdir -p $DIR/kustomize/kubeadm/init-patches
    rm -rf $DIR/kustomize/kubeadm/join-patches
    mkdir -p $DIR/kustomize/kubeadm/join-patches

    if [ -n "$USE_STANDARD_PORT_RANGE" ]; then
        sed -i 's/80-60000/30000-32767/g'  $DIR/kustomize/kubeadm/init/kubeadm-cluster-config-v1beta2.yml
    fi
}

function apply_installer_crd() {
    INSTALLER_CRD_DEFINITION="$DIR/kurlkinds/cluster.kurl.sh_installers.yaml"
    kubectl apply -f "$INSTALLER_CRD_DEFINITION"

    if [ -z "$ONLY_APPLY_MERGED" ] && [ -n "$INSTALLER_YAML" ]; then
        ORIGINAL_INSTALLER_SPEC=/tmp/kurl-bin-utils/specs/original.yaml
        cat > $ORIGINAL_INSTALLER_SPEC <<EOL
${INSTALLER_YAML}
EOL
        kubectl apply -f "$ORIGINAL_INSTALLER_SPEC"
    fi

    kubectl apply -f "$MERGED_YAML_SPEC"

    installer_label_velero_exclude_from_backup
}

function installer_label_velero_exclude_from_backup() {
    if [ -n "$INSTALLER_ID" ]; then
        kubectl label --overwrite=true installer/"$INSTALLER_ID" velero.io/exclude-from-backup=true
    fi
}
