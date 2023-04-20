
function render_yaml() {
    eval "echo \"$(cat $DIR/yaml/$1)\""
}

function render_yaml_file() {
    eval "echo \"$(cat $1)\""
}

function render_yaml_file_2() {
    local file="$1"
    if [ ! -f "$file" ]; then
        logFail "File $file does not exist"
        return 1
    fi
    local data=
    data=$(< "$file")
    local delimiter="__apply_shell_expansion_delimiter__"
    local command="cat <<$delimiter"$'\n'"$data"$'\n'"$delimiter"
    eval "$command"
}

function render_file() {
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

    if ! grep -q "resources[ \"]*:" "$kustomization_file"; then
        echo "resources:" >> "$kustomization_file"
    fi

    sed -i "/resources:.*/a - $resource_file" "$kustomization_file"
}

function insert_bases() {
    local kustomization_file="$1"
    local base_file="$2"

    local kubectl_client_minor_version=
    if commandExists "kubectl" ; then
        kubectl_client_minor_version="$(kubectl version --short | grep -i client | awk '{ print $3 }' | cut -d '.' -f2)"
    else
        kubectl_client_minor_version="$(echo "$KUBERNETES_VERSION" | cut -d '.' -f2)"
    fi

    # bases was deprecated in kustomize v2.1.0 in favor of resources
    # https://github.com/kubernetes-sigs/kustomize/blob/661743c7e5bd8c3d9d6866b6bc0a6f0e0b0512eb/site/content/en/blog/releases/v2.1.0.md
    # https://github.com/kubernetes-sigs/kustomize#kubectl-integration
    # Kubectl version: v1.14-v1.20, Kustomize version: v2.0.3
    if [ -n "$kubectl_client_minor_version" ] && [ "$kubectl_client_minor_version" -gt "20" ]; then
        insert_resources "$kustomization_file" "$base_file"
        return
    fi

    if ! grep -q "bases[ \"]*:" "$kustomization_file"; then
        echo "bases:" >> "$kustomization_file"
    fi

    sed -i "/bases:.*/a - $base_file" "$kustomization_file"
}

function insert_patches_json_6902() {
    local kustomization_file="$1"
    local patch_file="$2"
    local group="$3"
    local version="$4"
    local kind="$5"
    local name="$6"
    local namespace="$7"

    if ! grep -q "patchesJson6902" "$kustomization_file"; then
        echo "patchesJson6902:" >> "$kustomization_file"
    fi

# 'fourspace_' and 'twospace_' are used because spaces at the beginning of each line are stripped
    sed -i "/patchesJson6902.*/a- target:\n\
fourspace_ group: $group\n\
fourspace_ version: $version\n\
fourspace_ kind: $kind\n\
fourspace_ name: $name\n\
fourspace_ namespace: $namespace\n\
twospace_ path: $patch_file"       "$kustomization_file"

    sed -i "s/fourspace_ /    /" "$kustomization_file"
    sed -i "s/twospace_ /  /" "$kustomization_file"
}

function setup_kubeadm_kustomize() {
    local rsync_exclude=
    local kubeadm_conf_api=
    local kubeadm_cluster_config_v1beta2_file="kubeadm-cluster-config-v1beta2.yml"
    local kubeadm_cluster_config_v1beta3_file="kubeadm-cluster-config-v1beta3.yml"
    local kubeadm_init_config_v1beta2_file="kubeadm-init-config-v1beta2.yml"
    local kubeadm_init_config_v1beta3_file="kubeadm-init-config-v1beta3.yml"
    local kubeadm_join_config_v1beta2_file="kubeadm-join-config-v1beta2.yml"
    local kubeadm_join_config_v1beta3_file="kubeadm-join-config-v1beta3.yml"
    local kubeadm_init_src="$DIR/kustomize/kubeadm/init-orig"
    local kubeadm_join_src="$DIR/kustomize/kubeadm/join-orig"
    local kubeadm_init_dst="$DIR/kustomize/kubeadm/init"
    local kubeadm_join_dst="$DIR/kustomize/kubeadm/join"
    kubeadm_conf_api=$(kubeadm_conf_api_version)

    # Kubernete 1.22+ will use kubeadm/v1beta3 API
    # See: https://kubernetes.io/blog/2021/08/04/kubernetes-1-22-release-announcement/#more-secure-control-plane-with-kubeadm
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "22" ]; then
        # only include kubeadm/v1beta3 resources
        rsync_exclude="--exclude=$kubeadm_cluster_config_v1beta2_file --exclude=$kubeadm_init_config_v1beta2_file --exclude=$kubeadm_join_config_v1beta2_file"
        insert_resources "$kubeadm_init_src/kustomization.yaml" "$kubeadm_cluster_config_v1beta3_file"
        insert_resources "$kubeadm_init_src/kustomization.yaml" "$kubeadm_init_config_v1beta3_file"
        insert_resources "$kubeadm_join_src/kustomization.yaml" "$kubeadm_join_config_v1beta3_file"
    else
        # only include kubeadm/v1beta2 resources
        rsync_exclude="--exclude=$kubeadm_cluster_config_v1beta3_file --exclude=$kubeadm_init_config_v1beta3_file --exclude=$kubeadm_join_config_v1beta3_file"
        insert_resources "$kubeadm_init_src/kustomization.yaml" "$kubeadm_cluster_config_v1beta2_file"
        insert_resources "$kubeadm_init_src/kustomization.yaml" "$kubeadm_init_config_v1beta2_file"
        insert_resources "$kubeadm_join_src/kustomization.yaml" "$kubeadm_join_config_v1beta2_file"
    fi

    # Clean up the source directories for the kubeadm kustomize resources and
    # patches.
    rm -rf "$DIR/kustomize/kubeadm/init"
    rm -rf "$DIR/kustomize/kubeadm/join"
    rm -rf "$DIR/kustomize/kubeadm/init-patches"
    rm -rf "$DIR/kustomize/kubeadm/join-patches"

    # copy kubeadm kustomize resources
    eval rsync -avr "$rsync_exclude" "$kubeadm_init_src/" "$kubeadm_init_dst"
    eval rsync -avr "$rsync_exclude" "$kubeadm_join_src/" "$kubeadm_join_dst" 
    
    # create kubeadm kustomize patches directories
    mkdir -p "$DIR/kustomize/kubeadm/init-patches"
    mkdir -p "$DIR/kustomize/kubeadm/join-patches"

    if [ -n "$USE_STANDARD_PORT_RANGE" ]; then
        sed -i 's/80-60000/30000-32767/g'  "$DIR/kustomize/kubeadm/init/kubeadm-cluster-config-$kubeadm_conf_api.yml"
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

    try_1m kubectl apply -f "$MERGED_YAML_SPEC"

    installer_label_velero_exclude_from_backup
}

function installer_label_velero_exclude_from_backup() {
    if [ -n "$INSTALLER_ID" ]; then
        kubectl label --overwrite=true installer/"$INSTALLER_ID" velero.io/exclude-from-backup=true
    fi
}
