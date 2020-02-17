
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
    sed -i "s/{{ KubernetesVersion }}/$KUBERNETES_VERSION/" "$1"

    sed -i "s/{{ BootstrapToken }}/$BOOTSTRAP_TOKEN/" "$1"

    sed -i "s/{{ BootstrapTokenTTL }}/$BOOTSTRAP_TOKEN_TTL/" "$1"

    if [ -z $LOAD_BALANCER_ADDRESS ]; then
        sed -i "s/{{ LoadBalancerAddress }}/$LOAD_BALANCER_ADDRESS/" "$1"
    else
        sed -i "s/{{ HACluster }}/true/" "$1"
        sed -i "s/{{ LoadBalancerAddress }}/$LOAD_BALANCER_ADDRESS/" "$1"
    fi

    # if $LOAD_BALANCER_ADDRESS is set HACluster is already set to true and this block is ignored
    if [ -z $HA_CLUSTER ]; then
        sed -i "s/{{ HACluster }}/false/" "$1"
    else
        sed -i "s/{{ HACluster }}/true/" "$1"
    fi

    if [ -z $K8S_UPGRADE_PATCH_VERSION ]; then
        sed -i "s/{{ KubernetesUpgradePatchVersion }}/false/" "$1"
    else
        sed -i "s/{{ KubernetesUpgradePatchVersion }}/true/" "$1"
    fi

    sed -i "s/{{ KubernetesMasterAddress }}/$KUBERNETES_MASTER_ADDR/" "$1"

    sed -i "s/{{ APIServiceAddress }}/$API_SERVICE_ADDRESS/" "$1"

    sed -i "s/{{ KubeadmTokenCAHash }}/$KUBEADM_TOKEN_CA_HASH/" "$1"

    if [ -z $MASTER ]; then
        sed -i "s/{{ ControlPlane }}/false/" "$1"
    else
        sed -i "s/{{ ControlPlane }}/true/" "$1"
    fi

    sed -i "s/{{ CertKey }}/$CERT_KEY/" "$1"

    sed -i "s/{{ ServiceCIDR }}/$SERVICE_CIDR/" "$1"

    sed -i "s/{{ ServiceCIDRRange }}/$SERVICE_CIDR_RANGE/" "$1"
}

function docker_yaml() {
    sed -i "s/{{ DockerVersion }}/$DOCKER_VERSION/" "$1"

    if [ -z $BYPASS_STORAGEDRIVER_WARNING ]; then
        sed -i "s/{{ BypassStoragedriverWarning }}/false/" "$1"
    else
        sed -i "s/{{ BypassStoragedriverWarning }}/true/" "$1"
    fi

    if [ -z $SKIP_DOCKER_INSTA:: ]; then
        sed -i "s/{{ NoDocker }}/false/" "$1"
    else
        sed -i "s/{{ NoDocker }}/true/" "$1"
    fi

    if [ -z $NO_CE_ON_EE ]; then
        sed -i "s/{{ NoCEOnEE }}/false/" "$1"
    else
        sed -i "s/{{ NoCEOnEE }}/true/" "$1"
    fi

    if [ -z $HARD_FAIL_ON_LOOPBACK ]; then
        sed -i "s/{{ HardFailOnLoopback }}/false/" "$1"
    else
        sed -i "s/{{ HardFailOnLoopback }}/true/" "$1"
    fi

    sed -i "s/{{ AdditonalNoProxy }}/$ADDITIONAL_NO_PROXY/" "$1"

    sed -i "s/{{ DockerRegistryIp }}/$DOCKER_REGISTRY_IP/" "$1"
}

function kotsadm_yaml() {
    sed -i "s/{{ KotsadmVersion }}/$KOTSADM_VERSION/" "$1"

    sed -i "s/{{ KotsadmApplicationSlug }}/$KOTSADM_APPLICATION_SLUG/" "$1"

    sed -i "s/{{ KotsadmHostname }}/$KOTSADM_HOSTNAME/" "$1"

    if [ -z $KOTSADM_UI_BIND_PORT ]; then
        sed -i "s/{{ KotsadmUIBindPort }}/0/" "$1"
    else
        sed -i "s/{{ KotsadmUIBindPort }}/$KOTSADM_UI_BIND_PORT/" "$1"
    fi

    sed -i "s/{{ KotsadmApplicationNamepsaces }}/$KOTSADM_APPLICATION_NAMESPACES/" "$1"

    sed -i "s/{{ KotsadmAlpha }}/$KOTSADM_ALPHA/" "$1"
}

function contour_yaml() {
    sed -i "s/{{ ContourVersion }}/$CONTOUR_VERSION/" "$1"
}

function prometheus_yaml() {
    sed -i "s/{{ PrometheusVersion }}/$PROMETHEUS_VERSION/" "$1"
}

function rook_yaml() {
    sed -i "s/{{ RookVersion }}/$ROOK_VERSION/" "$1"

    sed -i "s/{{ StorageClass }}/$STORAGE_CLASS/" "$1"

    if [ -z $CEPH_POOL_REPLICAS ]; then
        sed -i "s/{{ CephPoolReplicas }}/0/" "$1"
    else
        sed -i "s/{{ CephPoolReplicas }}/$CEPH_POOL_REPLICAS/" "$1"
    fi
}

function fluentd_yaml() {
    sed -i "s/{{ FluentdVersion }}/$FLUENTD_VERSION/" "$1"

    if [ -z $FLUENTD_FULL_EFK_STACK ]; then
        sed -i "s/{{ EfkStack }}/false/" "$1"
    else
        sed -i "s/{{ EfkStack }}/true/" "$1"
    fi
}

function weave_yaml() {
    sed -i "s/{{ WeaveVersion }}/$WEAVE_VERSION/" "$1"

    sed -i "s/{{ EncryptNetwork }}/$ENCRYPT_NETWORK/" "$1"

    sed -i "s/{{ IPAllocRange }}/$IP_ALLOC_RANGE/" "$1"

    sed -i "s/{{ PodCIDR }}/$POD_CIDR/" "$1"

    sed -i "s/{{ PodCIDRRange }}/$POD_CIDR_RANGE/" "$1"
}

function registry_yaml() {
    sed -i "s/{{ RegistryVersion }}/$REGISTRY_VERSION/" "$1"

    sed -i "s/{{ RegistryPublishPort }}/$REGISTRY_PUBLISH_PORT/" "$1"
}


function velero_yaml() {
    sed -i "s/{{ VeleroVersion }}/$VELERO_VERSION/" "$1"

    sed -i "s/{{ VeleroNamespace }}/$VELERO_NAMESPACE/" "$1"

    if [ -z $VELERO_LOCAL_BUCKET ]; then
        sed -i "s/{{ VeleroLocalBucket }}/false/" "$1"
    else
        sed -i "s/{{ VeleroLocalBucket }}/true/" "$1"
    fi

    if [ -z $VELERO_INSTALL_CLI ]; then
        sed -i "s/{{ VeleroInstallCLI }}/false/" "$1"
    else
        sed -i "s/{{ VeleroInstallCLI }}/true/" "$1"
    fi

    if [ -z $VELERO_INSTALL_CLI ]; then
        sed -i "s/{{ VeleroUseRestic }}/false/" "$1"
    else
        sed -i "s/{{ VeleroUseRestic }}/true/" "$1"
    fi
}

function minio_yaml() {
    sed -i "s/{{ MinioVersion }}/$MINIO_VERSION/" "$1"
    sed -i "s/{{ MinioNamespace }}/$MINIO_NAMESPACE/" "$1"
}

function openebs_yaml() {
    sed -i "s/{{ OpenEBSVersion }}/$OPENEBS_VERSION/" "$1"
    sed -i "s/{{ OpenEBSNamespace }}/$OPENEBS_NAMESPACE/" "$1"
    sed -i "s/{{ OpenEBSLocalPV }}/$OPENEBS_LOCALPV/" "$1"
    sed -i "s/{{ OpenEBSLocalPVStorageClass }}/$OPENEBS_LOCAL_PV_STORAGE_CLASS/" "$1"
}

function flags_yaml() {

    if [ -z $AIRGAP ]; then
        sed -i "s/{{ Airgap }}/false/" "$1"
    else
        sed -i "s/{{ Airgap }}/true/" "$1"
    fi

    if [ -z $NO_PROXY ]; then
        sed -i "s/{{ NoProxy }}/false/" "$1"
    else
        sed -i "s/{{ NoProxy }}/true/" "$1"
    fi

    sed -i "s/{{ HostnameCheck }}/$HOSTNAME_CHECK/" "$1"

    sed -i "s/{{ HTTPProxy }}/$PROXY_ADDRESS/" "$1"

    if [ -z $BYPASS_STORAGEDRIVER_WARNINGS ]; then
        sed -i "s/{{ BypassStorageDriverWarning }}/false/" "$1"
    else
        sed -i "s/{{ BypassStorageDriverWarning }}/true/" "$1"
    fi

    sed -i "s/{{ PrivateAddress }}/$PRIVATE_ADDRESS/" "$1"

    sed -i "s/{{ PublicAddress }}/$PUBLIC_ADDRESS/" "$1"

    if [ -z $HARD_FAIL_ON_FIREWALLD ]; then
        sed -i "s/{{ HardFailOnFirewallD }}/false/" "$1"
    else
        sed -i "s/{{ HardFailOnFirewallD }}/true/""$1"
    fi

    if [ -z $BYPASS_FIREWALLD_WARNING ]; then
        sed -i "s/{{ BypassFirewallDWarning }}/false/" "$1"
    else
        sed -i "s/{{ BypassFirewallDWarning }}/true/" "$1"
    fi

    sed -i "s/{{ Task }}/$TASK/" "$1"
}

function apply_flags_to_yaml() {
    kubernetes_yaml "$1"
    docker_yaml "$1"
    kotsadm_yaml "$1"
    weave_yaml "$1"
    contour_yaml "$1"
    rook_yaml "$1"
    registry_yaml "$1"
    prometheus_yaml "$1"
    fluentd_yaml "$1"
    velero_yaml "$1"
    minio_yaml "$1"
    openebs_yaml "$1"
    flags_yaml "$1"
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
DOCKER_VERSION=poop
NO_PROXY=1
KUBERNETES_VERSION="latest"
WEAVE_VERSION="latest"
MINIO_VERSION="latest"
OPENEBS_VERSION="latest"
PROMETHEUS_VERSION="latest"
FLUENTD_VERSION="latest"
ROOK_VERSION="latest"
REGISTRY_VERSION="latest"
VELERO_VERSION="latest"
CONTOUR_VERSION="latest"
KOTSADM_VERSION="latest"

apply_flags_to_yaml "$1"
