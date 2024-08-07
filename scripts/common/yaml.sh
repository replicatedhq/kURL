#!/bin/bash

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

    # we care about the current kubernetes version here, not the target version - this function can be called from pre-init addons
    local kubeletVersion=
    kubeletVersion="$(kubelet_version)"
    semverParse "$kubeletVersion"
    local kubeletMinor="$minor"

#    # Kubernetes 1.27 uses kustomize v5 which dropped support for old, legacy style patches
#    # See: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.27.md#changelog-since-v1270
#    if [ "$kubeletMinor" -ge "27" ]; then
#        if [[ $kustomization_file =~ "prometheus" ]] || [[ $kustomization_file =~ "rook" ]]; then
#            # TODO: multi-doc patches is not currently supported in kustomize v5
#            # continue using the deprecated 'patchesStrategicMerge' field until this is fixed
#            # Ref: https://github.com/kubernetes-sigs/kustomize/issues/5040
#            if ! grep -q "patchesStrategicMerge" "$kustomization_file"; then
#                echo "patchesStrategicMerge:" >> "$kustomization_file"
#            fi
#            sed -i "/patchesStrategicMerge.*/a - $patch_file" "$kustomization_file"
#        else
#            if ! grep -q "^patches:" "$kustomization_file"; then
#                echo "patches:" >> "$kustomization_file"
#            fi
#            sed -i "/patches:/a - path: $patch_file" "$kustomization_file"
#        fi
#        return
#    fi

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
        kubectl_client_minor_version="$(kubectl_client_version | cut -d '.' -f2)"
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
    local kubeadm_exclude=
    local kubeadm_conf_api=
    local kubeadm_cluster_config_v1beta2_file="kubeadm-cluster-config-v1beta2.yml"
    local kubeadm_cluster_config_v1beta3_file="kubeadm-cluster-config-v1beta3.yml"
    local kubeadm_init_config_v1beta2_file="kubeadm-init-config-v1beta2.yml"
    local kubeadm_init_config_v1beta3_file="kubeadm-init-config-v1beta3.yml"
    local kubeadm_join_config_v1beta2_file="kubeadm-join-config-v1beta2.yaml"
    local kubeadm_join_config_v1beta3_file="kubeadm-join-config-v1beta3.yaml"
    local kubeadm_init_src="$DIR/kustomize/kubeadm/init-orig"
    local kubeadm_join_src="$DIR/kustomize/kubeadm/join-orig"
    local kubeadm_init_dst="$DIR/kustomize/kubeadm/init"
    local kubeadm_join_dst="$DIR/kustomize/kubeadm/join"
    kubeadm_conf_api=$(kubeadm_conf_api_version)

    # Clean up the source directories for the kubeadm kustomize resources and
    # patches.
    rm -rf "$DIR/kustomize/kubeadm/init"
    rm -rf "$DIR/kustomize/kubeadm/join"
    rm -rf "$DIR/kustomize/kubeadm/init-patches"
    rm -rf "$DIR/kustomize/kubeadm/join-patches"

    # Kubernete 1.26+ will use kubeadm/v1beta3 API
    if [ "$KUBERNETES_TARGET_VERSION_MINOR" -ge "26" ]; then
        # only include kubeadm/v1beta3 resources
        kubeadm_exclude=("$kubeadm_cluster_config_v1beta2_file" "$kubeadm_init_config_v1beta2_file" "$kubeadm_join_config_v1beta2_file")
    else
        # only include kubeadm/v1beta2 resources
        kubeadm_exclude=("$kubeadm_cluster_config_v1beta3_file" "$kubeadm_init_config_v1beta3_file" "$kubeadm_join_config_v1beta3_file")
    fi

    # copy kubeadm kustomize resources
    copy_kustomize_kubeadm_resources "$kubeadm_init_src" "$kubeadm_init_dst" "${kubeadm_exclude[@]}"
    copy_kustomize_kubeadm_resources "$kubeadm_join_src" "$kubeadm_join_dst" "${kubeadm_exclude[@]}"

    # tell kustomize which resources to generate
    # NOTE: 'eval' is used so that variables embedded within variables can be rendered correctly in the shell
    eval insert_resources "$kubeadm_init_dst/kustomization.yaml" "\$kubeadm_cluster_config_${kubeadm_conf_api}_file"
    eval insert_resources "$kubeadm_init_dst/kustomization.yaml" "\$kubeadm_init_config_${kubeadm_conf_api}_file"
    eval insert_resources "$kubeadm_join_dst/kustomization.yaml" "\$kubeadm_join_config_${kubeadm_conf_api}_file"

    # create kubeadm kustomize patches directories
    mkdir -p "$DIR/kustomize/kubeadm/init-patches"
    mkdir -p "$DIR/kustomize/kubeadm/join-patches"

    if [ -n "$USE_STANDARD_PORT_RANGE" ]; then
        sed -i 's/80-60000/30000-32767/g'  "$DIR/kustomize/kubeadm/init/kubeadm-cluster-config-$kubeadm_conf_api.yml"
    fi
}

# copy_kustomize_kubeadm_resources copies kubeadm kustomize resources
# from source ($1) to destination ($2) and excludes files specified as
# variable number of arguments.
# E.g. copy_kustomize_kubeadm_resources \
#       "/var/lib/kurl/kustomize/kubeadm/init-orig" \
#       "/var/lib/kurl/kustomize/kubeadm/init" \
#       "kubeadm-cluster-config-v1beta2.yml" \
#       "kubeadm-init-config-v1beta2.yml" \
#       "kubeadm-join-config-v1beta2.yml"
function copy_kustomize_kubeadm_resources() {
    local kustomize_kubeadm_src_dir=$1
    local kustomize_kubeadm_dst_dir=$2
    local excluded_files=("${@:3}")

    # ensure destination exist
    mkdir -p "$kustomize_kubeadm_dst_dir"

    # copy kustomize resources from source to destination directory
    # but exclude files in $excluded_files.
    for file in "$kustomize_kubeadm_src_dir"/*; do
        filename=$(basename "$file")
        excluded=false
        for excluded_file in "${excluded_files[@]}"; do
            if [ "$filename" = "$excluded_file" ]; then
                excluded=true
                break
            fi
        done
        if ! $excluded; then
            cp "$file" "$kustomize_kubeadm_dst_dir"
        fi
    done
}

function apply_installer_crd() {
    INSTALLER_CRD_DEFINITION="$DIR/kurlkinds/cluster.kurl.sh_installers.yaml"
    kubectl apply -f "$INSTALLER_CRD_DEFINITION"

    if [ -z "$ONLY_APPLY_MERGED" ] && [ -n "$INSTALLER_YAML" ]; then
        ORIGINAL_INSTALLER_SPEC=/tmp/kurl-bin-utils/specs/original.yaml
        cat > $ORIGINAL_INSTALLER_SPEC <<EOL
${INSTALLER_YAML}
EOL
        try_1m kubectl apply -f "$ORIGINAL_INSTALLER_SPEC"
    fi

    try_1m kubectl apply -f "$MERGED_YAML_SPEC"

    installer_label_velero_exclude_from_backup
}

function installer_label_velero_exclude_from_backup() {
    if [ -n "$INSTALLER_ID" ]; then
        kubectl label --overwrite=true installer/"$INSTALLER_ID" velero.io/exclude-from-backup=true
    fi
}

# yaml_indent indents each line of stdin with the given indent
function yaml_indent() {
    local indent=$1
    sed -e "s/^/$indent/"
}

# yaml_escape_string_quotes escapes string quotes for use in a yaml file
function yaml_escape_string_quotes() {
    sed -e 's/"/\\"/g'
}

# yaml_newline_to_literal replaces newlines with \n
function yaml_newline_to_literal() {
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# get_yaml_from_multidoc_yaml reads a single file multi-doc yaml and finds a particular embedded yaml doc
# based on the `name:` field and outputs the doc to stdout.
function get_yaml_from_multidoc_yaml() {
    local multidoc_yaml="$1"
    local resource_name="$2"

    # use awk to split the multidoc file using `---`separator
    awk -v RS='---\n' -v ORS='---\n' -v RESOURCE_NAME="$resource_name" '
        $0 ~ ("name: " RESOURCE_NAME) {
            found = 1
            print $0
        }
        END {
            exit !found
        }
    ' "$multidoc_yaml"
}
