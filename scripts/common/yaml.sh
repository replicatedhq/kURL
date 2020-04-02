
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
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ contourVersion __kurl__" "$CONTOUR_VERSION"
}

function docker_yaml() {
    local filename=$1
    local addon_name="docker"

    if [ -z $DOCKER_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ dockerAdditonalNoProxy __kurl__" "$ADDITIONAL_NO_PROXY"
    replace_with_true_or_false $filename "__kurl__ dockerBypassStoragedriverWarning __kurl__" "$BYPASS_STORAGEDRIVER_WARNING"
    replace_with_variable_or_delete_line $filename "__kurl__ dockerRegistryIP __kurl__" "$DOCKER_REGISTRY_IP"
    replace_with_true_or_false $filename "__kurl__ dockerHardFailOnLoopback __kurl__" "$HARD_FAIL_ON_LOOPBACK"
    replace_with_true_or_false $filename "__kurl__ dockerNoCEOnEE __kurl__" "$NO_CE_ON_EE"
    replace_with_true_or_false $filename "__kurl__ dockerNoDocker __kurl__" "$SKIP_DOCKER_INSTA"
    replace_with_variable_or_delete_line $filename "__kurl__ dockerVersion __kurl__" "$DOCKER_VERSION"
}

function fluentd_yaml() {
    local filename=$1
    local addon_name="fluentd"

    if [ -z $FLUENTD_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_true_or_false $filename "__kurl__ fluentdFullEFKStack __kurl__" "$FLUENTD_FULL_EFK_STACK"
    replace_with_variable_or_delete_line $filename "__kurl__ fluentdVersion __kurl__" "$FLUENTD_VERSION"
}

function kotsadm_yaml() {
    local filename=$1
    local addon_name="kotsadm"

    if [ -z $KOTSADM_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ kotsadmApplicationNamespace __kurl__" "$KOTSADM_APPLICATION_NAMESPACE"
    replace_with_variable_or_delete_line $filename "__kurl__ kotsadmApplicationSlug __kurl__" "$KOTSADM_APPLICATION_SLUG"
    replace_with_variable_or_delete_line $filename "__kurl__ kotsadmHostname __kurl__" "$KOTSADM_HOSTNAME"
    replace_with_variable_or_delete_line $filename "__kurl__ kotsadmUIBindPort __kurl__" "$KOTSADM_UI_BIND_PORT"
    replace_with_variable_or_delete_line $filename "__kurl__ kotsadmVersion __kurl__" "$KOTSADM_VERSION"
}

function kubernetes_yaml() {
    local filename=$1
    local addon_name="kubernetes"

    if [ -z $KUBERNETES_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_true_or_false $filename  "__kurl__ kubernetesHACluster __kurl__" "$HA_CLUSTER"
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesBootstrapToken __kurl__" "$BOOTSTRAP_TOKEN"
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesBootstrapTokenTTL __kurl__" "$BOOTSTRAP_TOKEN_TTL"
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesCertKey __kurl__" "$CERT_KEY"
    replace_with_true_or_false $filename  "__kurl__ kubernetesControlPlane __kurl__" $MASTER
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesKubeadmTokenCAHash __kurl__" "$KUBEADM_TOKEN_CA_HASH"

    #HA_CLUSTER will eventually be deprectated
    if [ -z $LOAD_BALANCER_ADDRESS ]; then
        replace_with_variable_or_delete_line $filename "__kurl__ kubernetesLoadBalancerAddress __kurl__" "$LOAD_BALANCER_ADDRESS"
        replace_with_true_or_false $filename "__kurl__ kubernetesLoadBalancerAddress __kurl__" "$HA_CLUSTER"
    else
        # if $LOAD_BALANCER_ADDRESS is set HACluster is also set to true
        replace_with_variable_or_delete_line $filename "__kurl__ kubernetesLoadBalancerAddress __kurl__" "$LOAD_BALANCER_ADDRESS"
        sed -i "s/__kurl__ kubernetesHACluster __kurl__/true/" "$1"
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesMasterAddress __kurl__" "$KUBERNETES_MASTER_ADDR"
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesServiceCIDR __kurl__" "$SERVICE_CIDR"
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesServiceCIDRRange __kurl__" "$SERVICE_CIDR_RANGE"
    replace_with_variable_or_delete_line $filename "__kurl__ kubernetesVersion __kurl__" "$KUBERNETES_VERSION"
}

function flags_yaml() {
    local filename=$1

    replace_with_variable_or_delete_line $filename "__kurl__ HTTPProxy __kurl__" "$PROXY_ADDRESS"
    replace_with_true_or_false $filename "__kurl__ Airgap __kurl__" $AIRGAP
    replace_with_true_or_false $filename "__kurl__ BypassFirewalldWarning __kurl__" "$BYPASS_FIREWALLD_WARNING"
    replace_with_true_or_false $filename "__kurl__ HardFailOnFirewalld __kurl__" "$HARD_FAIL_ON_FIREWALLD"
    replace_with_variable_or_delete_line $filename "__kurl__ HostnameCheck __kurl__" "$HOSTNAME_CHECK"
    replace_with_true_or_false $filename "__kurl__ NoProxy __kurl__" $NO_PROXY
    replace_with_variable_or_delete_line $filename "__kurl__ PrivateAddress __kurl__" "$PRIVATE_ADDRESS"
    replace_with_variable_or_delete_line $filename "__kurl__ PublicAddress __kurl__" "$PUBLIC_ADDRESS"
    replace_with_variable_or_delete_line $filename "__kurl__ Task __kurl__" "$TASK"
}

function minio_yaml() {
    local filename=$1
    local addon_name="minio"

    if [ -z $MINIO_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ minioNamespace __kurl__" "$MINIO_NAMESPACE"
    replace_with_variable_or_delete_line $filename "__kurl__ minioVersion __kurl__" "$MINIO_VERSION"
}

function openebs_yaml() {
    local filename=$1
    local addon_name="openEBS"

    if [ -z $OPENEBS_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ openEBSNamespace __kurl__" "$OPENEBS_NAMESPACE"
    replace_with_true_or_false $filename "__kurl__ openEBSIsLocalPVEnabled __kurl__" "$OPENEBS_LOCALPV"
    replace_with_variable_or_delete_line $filename "__kurl__ openEBSLocalPVStorageClassName __kurl__" "$OPENEBS_LOCALPV_STORAGE_CLASS"
    replace_with_variable_or_delete_line $filename "__kurl__ openEBSVersion __kurl__" "$OPENEBS_VERSION"
    replace_with_true_or_false $filename "__kurl__ openEBSIsCstorEnabled __kurl__" "$OPENEBS_CSTOR"
    replace_with_variable_or_delete_line $filename "__kurl__ openEBSCstorStorageClassName __kurl__" "$OPENEBS_CSTOR_STORAGE_CLASS"
}

function prometheus_yaml() {
    local filename=$1
    local addon_name="prometheus"

    if [ -z $PROMETHEUS_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ prometheusVersion __kurl__" "$PROMETHEUS_VERSION"
}

function registry_yaml() {
    local filename=$1
    local addon_name="registry"

    if [ -z $REGISTRY_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ registryPublishPort __kurl__" "$REGISTRY_PUBLISH_PORT"
    replace_with_variable_or_delete_line $filename "__kurl__ registryVersion __kurl__" "$REGISTRY_VERSION"
}

function rook_yaml() {
    local filename=$1
    local addon_name="rook"

    if [ -z $ROOK_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_variable_or_delete_line $filename "__kurl__ rookStorageClassName __kurl__" "$STORAGE_CLASS"
    replace_with_variable_or_delete_line $filename "__kurl__ rookCephReplicaCount __kurl__" "$CEPH_POOL_REPLICAS"
    replace_with_variable_or_delete_line $filename "__kurl__ rookVersion __kurl__" "$ROOK_VERSION"
    replace_with_true_or_false $filename "__kurl__ rookIsBlockStorageEnabled __kurl__" "$ROOK_BLOCK_STORAGE_ENABLED"
    replace_with_variable_or_delete_line $filename "__kurl__ rookBlockDeviceFilter __kurl__" "$ROOK_BLOCK_DEVICE_FILTER"
}

function velero_yaml() {
    local filename=$1
    local addon_name="velero"

    if [ -z $VELERO_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_true_or_false $filename "__kurl__ veleroDisableRestic __kurl__" "$VELERO_USE_RESTIC"
    replace_with_true_or_false $filename "__kurl__ veleroDisableCLI __kurl__" "$VELERO_DISABLE_CLI"
    replace_with_variable_or_delete_line $filename "__kurl__ veleroLocalBucket __kurl__" "$VELERO_LOCAL_BUCKET"
    replace_with_variable_or_delete_line $filename "__kurl__ veleroNamespace __kurl__" "$VELERO_NAMESPACE"
    replace_with_variable_or_delete_line $filename "__kurl__ veleroVersion __kurl__" "$VELERO_VERSION"
}

function weave_yaml() {
    local filename=$1
    local addon_name="weave"

    if [ -z $WEAVE_VERSION ]; then
        sed -i "/$addon_name/d" $filename
        return 0
    fi

    replace_with_true_or_false $filename "__kurl__ weaveisEncryptionDisabled __kurl__" "$ENCRYPT_NETWORK"
    replace_with_variable_or_delete_line $filename "__kurl__ weavePodCIDR __kurl__" "$WEAVE_POD_CIDR"
    replace_with_variable_or_delete_line $filename "__kurl__ weavePodCIDRRange __kurl__" "$WEAVE_POD_CIDR_RANGE"
    replace_with_variable_or_delete_line $filename "__kurl__ weaveVersion __kurl__" "$WEAVE_VERSION"
}

function apply_flags_to_installer_yaml() {
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
    INSTALLER_CRD_DEFINITION="$DIR/kurlkinds/cluster.kurl.sh_installers.yaml"
    INSTALLER_TEMPLATE_OBJECT="$DIR/kurlkinds/cluster.kurl.sh_template.yaml"
    INSTALLER_MODIFIED_OBJECT="/tmp/kurl_install.yaml"

    kubectl apply -f $INSTALLER_CRD_DEFINITION

    cp $INSTALLER_TEMPLATE_OBJECT $INSTALLER_MODIFIED_OBJECT

    apply_flags_to_installer_yaml $INSTALLER_MODIFIED_OBJECT

    kubectl apply -f $INSTALLER_MODIFIED_OBJECT

    rm $INSTALLER_MODIFIED_OBJECT
}
