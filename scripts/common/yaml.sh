
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

function kubernetes_yaml() {
    sed -i "s/{{ KubernetesVersion }}/$KUBERNETES_VERSION/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ BootstrapToken }}/$BOOTSTRAP_TOKEN/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ BootstrapTokenTTL }}/$BOOTSTRAP_TOKEN_TTL/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $LOAD_BALANCER_ADDRESS ]; then
        sed -i "s/{{ HACluster }}/true/"  $INSTALLER_BASE_YAML_FILE
        sed -i "s/{{ LoadBalancerAddress }}/$LOAD_BALANCER_ADDRESS/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ LoadBalancerAddress }}/$LOAD_BALANCER_ADDRESS/"  $INSTALLER_BASE_YAML_FILE
    fi

    # if $LOAD_BALANCER_ADDRESS is set HACluster is already set to true and this block is ignored
    if [ -z $HA_CLUSTER ]; then
        sed -i "s/{{ HACluster }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ HACluster }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    if [ -z $K8S_UPGRADE_PATCH_VERSION ]; then
        sed -i "s/{{ KubernetesUpgradePatchVersion }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ KubernetesUpgradePatchVersion }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    sed -i "s/{{ KubernetesMasterAddress }}/$KUBERNETES_MASTER_ADDR/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ APIServiceAddress }}/$API_SERVICE_ADDRESS/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ KubeadmTokenCAHash }}/$KUBEADM_TOKEN_CA_HASH/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $MASTER ]; then
        sed -i "s/{{ ControlPlane }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ ControlPlane }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    sed -i "s/{{ CertKey }}/$CERT_KEY/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ ServiceCIDR }}/$SERVICE_CIDR/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ ServiceCIDRRange }}/$SERVICE_CIDR_RANGE/"  $INSTALLER_BASE_YAML_FILE
}

function docker_yaml() {
    sed -i "s/{{ DockerVersion }}/$DOCKER_VERSION/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $BYPASS_STORAGEDRIVER_WARNING ]; then
        sed -i "s/{{ BypassStoragedriverWarning }}/true/"  $installer_base_yaml_file
    else
        sed -i "s/{{ BypassStoragedriverWarning }}/false/"  $installer_base_yaml_file
    fi

    if [ -z $SKIP_DOCKER_INSTA:: ]; then
        sed -i "s/{{ nodocker }}/true/"  $installer_base_yaml_file
    else
        sed -i "s/{{ nodocker }}/false/"  $installer_base_yaml_file
    fi

    if [ -z $NO_CE_ON_EE ]; then
        sed -i "s/{{ NoCEOnEE }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ NoCEOnEE }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    if [ -z $HARD_FAIL_ON_LOOPBACK ]; then
        sed -i "s/{{ HardFailOnLoopback }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ HardFailOnLoopback }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    sed -i "s/{{ AdditonalNoProxy }}/$ADDITIONAL_NO_PROXY/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ DockerRegistryIp }}/$DOCKER_REGISTRY_IP/"  $INSTALLER_BASE_YAML_FILE
}

function kotsadm_yaml() {
    sed -i "s/{{ KotsadmVersion}}/$KOTSADM_VERSION/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ KotsadmApplicationSlug}}/$KOTSADM_APPLICATION_SLUG/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ KotsadmHostname}}/$KOTSADM_HOSTNAME/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ KotsadmUIBindPort }}/$KOTSADM_UI_BIND_PORT/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ KotsadmApplicationNamepsaces }}/$KOTSADM_APPLICATION_NAMESPACES/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ KotsadmAlpha }}/$KOTSADM_ALPHA/"  $INSTALLER_BASE_YAML_FILE
}

function contour_yaml() {
    sed -i "s/{{ ContourVersion }}/$CONTOUR_VERSION/"  $INSTALLER_BASE_YAML_FILE
}

function prometheus_yaml() {
    sed -i "s/{{ PrometheusVersion }}/$PROMETHEUS_VERSION/"  $INSTALLER_BASE_YAML_FILE
}

function rook_yaml() {
    sed -i "s/{{ RookVersion }}/$ROOK_VERSION/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ StorageClass }}/$STORAGE_CLASS/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ CephPoolReplicas }}/$CEPH_POOL_REPLICAS/"  $INSTALLER_BASE_YAML_FILE
}

function fluentd_yaml() {
    sed -i "s/{{ FluentdVersion }}/$FLUENTD_VERSION/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $FLUENTD_FULL_EFK_STACK ]; then
        sed -i "s/{{ EfkStack }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ Efkstack }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi
}

function weave_yaml() {
    sed -i "s/{{ WeaveVersion }}/$WEAVE_VERSION/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ EncryptNetwork }}/$ENCRYPT_NETWORK/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ IPAllocRange }}/$IP_ALLOC_RANGE/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ PodCIDR }}/$POD_CIDR/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ PodCIDRRange }}/$POD_CIDR_RANGE/"  $INSTALLER_BASE_YAML_FILE
}

function registry_yaml() {
    sed -i "s/{{ RegistryVersion }}/$REGISTRY_VERSION/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ RegistryPublishPort }}/$REGISTRY_PUBLISH_PORT/"  $INSTALLER_BASE_YAML_FILE
}


function velero_yaml() {
    sed -i "s/{{ VeleroVersion }}/$VELERO_VERSION/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ VeleroNamespace }}/$VELERO_NAMESPACE/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $VELERO_LOCAL_BUCKET ]; then
        sed -i "s/{{ VeleroLocalBucket }}/true/"  $installer_base_yaml_file
    else
        sed -i "s/{{ VeleroLocalBucket }}/false/"  $installer_base_yaml_file
    fi

    if [ -z $VELERO_INSTALL_CLI ]; then
        sed -i "s/{{ VeleroInstallCLI }}/true/"  $installer_base_yaml_file
    else
        sed -i "s/{{ VeleroInstallCLI }}/false/"  $installer_base_yaml_file
    fi

    if [ -z $VELERO_INSTALL_CLI ]; then
        sed -i "s/{{ VeleroUseRestic }}/true/"  $installer_base_yaml_file
    else
        sed -i "s/{{ VeleroUseRestic }}/false/"  $installer_base_yaml_file
    fi
}

function minio_yaml() {
    sed -i "s/{{ MinioVersion }}/$MINIO_VERSION/"  $INSTALLER_BASE_YAML_FILE
    sed -i "s/{{ MinioNamespace }}/$MINIO_NAMESPACE/"  $INSTALLER_BASE_YAML_FILE
}

function openebs_yaml() {
    sed -i "s/{{ OpenEBSVersion }}/$OPENEBS_VERSION/"  $INSTALLER_BASE_YAML_FILE
    sed -i "s/{{ OpenEBSNamespace }}/$OPENEBS_NAMESPACE/"  $INSTALLER_BASE_YAML_FILE
    sed -i "s/{{ OpenEBSLocalPV }}/$OPENEBS_LOCALPV/"  $INSTALLER_BASE_YAML_FILE
    sed -i "s/{{ OpenEBSLocalPVStorageClass }}/$OPENEBS_LOCAL_PV_STORAGE_CLASS/"  $INSTALLER_BASE_YAML_FILE
}

function flags_yaml() {

    if [ -z $AIRGAP ]; then
        sed -i "s/{{ Airgap }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ Airgap }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    if [ -z $NO_PROXY ]; then
        sed -i "s/{{ NoProxy }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ NoProxy }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    sed -i "s/{{ HostnameCheck }}/$HOSTNAME_CHECK/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ HTTPProxy }}/$PROXY_ADDRESS/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $BYPASS_STORAGEDRIVER_WARNINGS ]; then
        sed -i "s/{{ BypassStorageDriverWarning }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ BypassStorageDriverWarning }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    sed -i "s/{{ PrivateAddress }}/$PRIVATE_ADDRESS/"  $INSTALLER_BASE_YAML_FILE

    sed -i "s/{{ PublicAddress }}/$PUBLIC_ADDRESS/"  $INSTALLER_BASE_YAML_FILE

    if [ -z $HARD_FAIL_ON_FIREWALLD ]; then
        sed -i "s/{{ HardFailOnFirewallD }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ HardFailOnFirewallD }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    if [ -z $BYPASS_FIREWALLD_WARNING ]; then
        sed -i "s/{{ BypassFirewallDWarning }}/true/"  $INSTALLER_BASE_YAML_FILE
    else
        sed -i "s/{{ BypassFirewallDWarning }}/false/"  $INSTALLER_BASE_YAML_FILE
    fi

    sed -i "s/{{ Task }}/$TASK/"  $INSTALLER_BASE_YAML_FILE
}


function apply_flags_to_yaml() {
    kubernetes_yaml
    docker_yaml
    kotsadm_yaml
    weave_yaml
    contour_yaml
    rook_yaml
    registry_yaml
    prometheus_yaml
    fluentd_yaml
    velero_yaml
    minio_yaml
    openebs_yaml
    flags_yaml
}


function setup_installer_crd() {
    CREATE_INSTALLER_CRD_YAML="$DIR/crd/cluster_v1beta1_installer.yaml"
    INSTALLER_BASE_YAML_FILE="/tmp/kurl_installer.yaml"

    kubectl apply -f $CREATE_INSTALLER_CRD_YAML

    cat > $INSTALLER_BASE_YAML_FILE << EOF
$INSTALLER_YAML
EOF

    apply_flags_to_installer_yaml $INSTALLER_YAML_BASE_FILE

    kubectl apply -f $INSTALLER_BASE_YAML_FILE

    rm $INSTALLER_BASE_YAML_FILE
}
