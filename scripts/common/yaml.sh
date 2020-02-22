
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
}

function replace_with_variable_or_delete_line() {
    #if the variable exists, replace with that variables value, otherwise delete the entire line
    local filename=$1
    local replace_string=$2
    local bash_variable=$3

    if [ -z $bash_variable ]; then
        sed -i "/$replace_string/d" "$filename"
    else
        sed -i "s|$replace_string|$bash_variable|" "$filename"
    fi
}

function replace_with_true_or_false() {
    #if the variable exists, replace with true, otherwise false
    local filename=$1
    local replace_string=$2
    local bash_variable=$3

    if [ -z $bash_variable ]; then
        sed -i "s|$replace_string|false|" "$filename"
    else
        sed -i "s|$replace_string|true|" "$filename"
    fi
}

function contour_yaml() {
    local filename=$1
    local addon_name="contour"

    if [ -z $CONTOUR_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ contourVersion ^^" "$CONTOUR_VERSION"
}

function docker_yaml() {
    local filename=$1
    local addon_name="docker"

    if [ -z $DOCKER_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ dockerAdditonalNoProxy ^^" "$ADDITIONAL_NO_PROXY"
    replace_with_true_or_false $filename "^^ dockerBypassStoragedriverWarning ^^" "$BYPASS_STORAGEDRIVER_WARNING"
    replace_with_variable_or_delete_line $filename "^^ dockerRegistryIP ^^" "$DOCKER_REGISTRY_IP"
    replace_with_true_or_false $filename "^^ dockerHardFailOnLoopback ^^" "$HARD_FAIL_ON_LOOPBACK"
    replace_with_true_or_false $filename "^^ dockerNoCEOnEE ^^" "$NO_CE_ON_EE"
    replace_with_true_or_false $filename "^^ dockerNoDocker ^^" "$SKIP_DOCKER_INSTA"
    replace_with_variable_or_delete_line $filename "^^ dockerVersion ^^" "$DOCKER_VERSION"
}

function fluentd_yaml() {
    local filename=$1
    local addon_name="fluentd"

    if [ -z $FLUENTD_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_true_or_false $filename "^^ fluentdFullEFKStack ^^" "$FLUENTD_FULL_EFK_STACK"
    replace_with_variable_or_delete_line $filename "^^ fluentdVersion ^^" "$FLUENTD_VERSION"
}

function kotsadm_yaml() {
    local filename=$1
    local addon_name="kotsadm"

    if [ -z $KOTSADM_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ kotsadmApplicationNamespace ^^" "$KOTSADM_APPLICATION_NAMESPACE"
    replace_with_variable_or_delete_line $filename "^^ kotsadmApplicationSlug ^^" "$KOTSADM_APPLICATION_SLUG"
    replace_with_variable_or_delete_line $filename "^^ kotsadmHostname ^^" "$KOTSADM_HOSTNAME"
    replace_with_variable_or_delete_line $filename "^^ kotsadmUIBindPort ^^" "$KOTSADM_UI_BIND_PORT"
    replace_with_variable_or_delete_line $filename "^^ kotsadmVersion ^^" "$KOTSADM_VERSION"
}

function kubernetes_yaml() {
    local filename=$1
    local addon_name="kubernetes"

    if [ -z $KUBERNETES_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ kubernetesAPIServiceAddress ^^" "$API_SERVICE_ADDRESS"
    replace_with_variable_or_delete_line $filename "^^ kubernetesBootstrapToken ^^" "$BOOTSTRAP_TOKEN"
    replace_with_variable_or_delete_line $filename "^^ kubernetesBootstrapTokenTTL ^^" "$BOOTSTRAP_TOKEN_TTL"
    replace_with_variable_or_delete_line $filename "^^ kubernetesCertKey ^^" "$CERT_KEY"
    replace_with_true_or_false $filename  "^^ kubernetesControlPlane ^^" $MASTER
    replace_with_variable_or_delete_line $filename "^^ kubernetesKubeadmTokenCAHash ^^" "$KUBEADM_TOKEN_CA_HASH"

    #HA_CLUSTER will eventually be deprectated
    if [ -z $LOAD_BALANCER_ADDRESS ]; then
        replace_with_variable_or_delete_line $filename "^^ kubernetesLoadBalancerAddress ^^" "$LOAD_BALANCER_ADDRESS"
        replace_with_true_or_false $filename "^^ kubernetesLoadBalancerAddress ^^" "$HA_CLUSTER"
    else
        # if $LOAD_BALANCER_ADDRESS is set HACluster is also set to true
        replace_with_variable_or_delete_line $filename "^^ kubernetesLoadBalancerAddress ^^" "$LOAD_BALANCER_ADDRESS"
        sed -i "s/^^ kubernetesHACluster ^^/true/" "$1"
    fi

    replace_with_variable_or_delete_line $filename "^^ kubernetesMasterAddress ^^" "$KUBERNETES_MASTER_ADDR"
    replace_with_variable_or_delete_line $filename "^^ kubernetesServiceCIDR ^^" "$SERVICE_CIDR"
    replace_with_variable_or_delete_line $filename "^^ kubernetesServiceCIDRRange ^^" "$SERVICE_CIDR_RANGE"
    replace_with_variable_or_delete_line $filename "^^ kubernetesVersion ^^" "$KUBERNETES_VERSION"
}

function flags_yaml() {
    local filename=$1

    replace_with_variable_or_delete_line $filename "^^ HTTPProxy ^^" "$PROXY_ADDRESS"
    replace_with_true_or_false $filename "^^ Airgap ^^" $AIRGAP
    replace_with_true_or_false $filename "^^ BypassFirewalldWarning ^^" "$BYPASS_FIREWALLD_WARNING"
    replace_with_true_or_false $filename "^^ HardFailOnFirewalld ^^" "$HARD_FAIL_ON_FIREWALLD"
    replace_with_variable_or_delete_line $filename "^^ HostnameCheck ^^" "$HOSTNAME_CHECK"
    replace_with_true_or_false $filename "^^ NoProxy ^^" $NO_PROXY
    replace_with_variable_or_delete_line $filename "^^ PrivateAddress ^^" "$PRIVATE_ADDRESS"
    replace_with_variable_or_delete_line $filename "^^ PublicAddress ^^" "$PUBLIC_ADDRESS"
    replace_with_variable_or_delete_line $filename "^^ Task ^^" "$TASK"
}

function minio_yaml() {
    local filename=$1
    local addon_name="minio"

    if [ -z $MINIO_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ minioNamespace ^^" "$MINIO_NAMESPACE"
    replace_with_variable_or_delete_line $filename "^^ minioVersion ^^" "$MINIO_VERSION"
}

function openebs_yaml() {
    local filename=$1
    local addon_name="openEBS"

    if [ -z $OPENEBS_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ openEBSNamespace ^^" "$OPENEBS_NAMESPACE"
    replace_with_true_or_false $filename "^^ openEBSLocalPV ^^" "$OPENEBS_LOCALPV"
    replace_with_variable_or_delete_line $filename "^^ openEBSLocalPVStorageClass ^^" "$OPENEBS_LOCALPV_STORAGE_CLASS"
    replace_with_variable_or_delete_line $filename "^^ openEBSVersion ^^" "$OPENEBS_VERSION"
}

function prometheus_yaml() {
    local filename=$1
    local addon_name="prometheus"

    if [ -z $PROMETHEUS_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ prometheusVersion ^^" "$PROMETHEUS_VERSION"
}

function registry_yaml() {
    local filename=$1
    local addon_name="registry"

    if [ -z $REGISTRY_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ registryPublishPort ^^" "$REGISTRY_PUBLISH_PORT"
    replace_with_variable_or_delete_line $filename "^^ registryVersion ^^" "$REGISTRY_VERSION"
}

function rook_yaml() {
    local filename=$1
    local addon_name="rook"

    if [ -z $ROOK_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_variable_or_delete_line $filename "^^ rookStorageClassName ^^" "$STORAGE_CLASS"
    replace_with_variable_or_delete_line $filename "^^ rookCephReplicaCount ^^" "$CEPH_POOL_REPLICAS"
    replace_with_variable_or_delete_line $filename "^^ rookVersion ^^" "$ROOK_VERSION"
}

function velero_yaml() {
    local filename=$1
    local addon_name="velero"

    if [ -z $VELERO_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_true_or_false $filename "^^ veleroDisableRestic ^^" "$VELERO_USE_RESTIC"
    replace_with_true_or_false $filename "^^ veleroDisableCLI ^^" "$VELERO_DISABLE_CLI"
    replace_with_variable_or_delete_line $filename "^^ veleroLocalBucket ^^" "$VELERO_LOCAL_BUCKET"
    replace_with_variable_or_delete_line $filename "^^ veleroNamespace ^^" "$VELERO_NAMESPACE"
    replace_with_variable_or_delete_line $filename "^^ veleroVersion ^^" "$VELERO_VERSION"
}

function weave_yaml() {
    local filename=$1
    local addon_name="weave"

    if [ -z $WEAVE_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        exit 1
    fi

    replace_with_true_or_false $filename "^^ weaveisEncryptionDisabled ^^" "$ENCRYPT_NETWORK"
    replace_with_variable_or_delete_line $filename "^^ weavePodCIDR ^^" "$WEAVE_POD_CIDR"
    replace_with_variable_or_delete_line $filename "^^ weavePodCIDRRange ^^" "$WEAVE_POD_CIDR_RANGE"
    replace_with_variable_or_delete_line $filename "^^ weaveVersion ^^" "$WEAVE_VERSION"
}

function apply_flags_to_yaml() {
    contour_yaml "$1"
    docker_yaml "$1"
    fluentd_yaml "$1"
    kotsadm_yaml "$1"
    kubernetes_yaml "$1"
    flags_yaml "$1"
    minio_yaml "$1"
    openebs_yaml "$1"
    prometheus_yaml "$1"
    registry_yaml "$1"
    rook_yaml "$1"
    velero_yaml "$1"
    weave_yaml "$1"
}

function setup_installer_crd() {
    INSTALLER_CRD_DEFINITION="$DIR/crd/cluster.kurl.sh_installers.yaml"
    INSTALLER_TEMPLATE_OBJECT="$DIR/crd/cluster.kurl.sh_template.yaml"
    INSTALLER_MODIFIED_OBJECT="/tmp/kurl_install.yaml"

    kubectl apply -f $INSTALLER_CRD_DEFINITION

    cp $INSTALLER_TEMPLATE_OBJECT $INSTALLER_MODIFIED_OBJECT

    cat > $INSTALL_MODIFIED_OBJECT << EOF
$INSTALLER_YAML
EOF

    apply_flags_to_installer_yaml $INSTALL_MODIFIED_OBJECT

    kubectl apply -f $INSTALL_MODIFIED_OBJECT

    rm $INSTALLER_MODIFIED_OBJECT
}
