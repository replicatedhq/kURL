STORAGE_CLASS=default

function rook() {
    case "$STORAGE_PROVISIONER" in
        rook|1)
            rookDeploy
            CEPH_DASHBOARD_URL=http://rook-ceph-mgr-dashboard.rook-ceph.svc.cluster.local:7000

            # Ceph v13+ requires login. Rook 1.0+ creates a secret in the rook-ceph namespace.
            cephDashboardPassword=$(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode)
            if [ -n "$cephDashboardPassword" ]; then
                CEPH_DASHBOARD_USER=admin
                CEPH_DASHBOARD_PASSWORD="$cephDashboardPassword"
            fi

            if isRook1; then
                MAINTAIN_ROOK_STORAGE_NODES=1
            fi
            ;;
        0|"")
            ;;
        *)
            bail "Error: unknown storage provisioner \"$STORAGE_PROVISIONER\""
            ;;
    esac
}

rookDeploy() {
    logStep "deploy rook"

    render_yaml rook-ceph-common.yaml > /tmp/rook-ceph-common.yaml
    render_yaml rook-ceph-operator.yaml > /tmp/rook-ceph-operator.yaml
    render_yaml rook-ceph-cluster.yaml > /tmp/rook-ceph-cluster.yaml
    render_yaml rook-ceph-block-pool.yaml > /tmp/rook-ceph-block-pool.yaml

    kubectl apply -f /tmp/rook-ceph-common.yaml
    kubectl apply -f /tmp/rook-ceph-operator.yaml

    spinnerRookReady # creating the cluster before the operator is ready fails

    kubectl apply -f /tmp/rook-ceph-cluster.yaml
    kubectl apply -f /tmp/rook-ceph-block-pool.yaml
    storageClassDeploy
 
    # wait for ceph dashboard password to be generated
    local delay=0.75
    local spinstr='|/-\'
    while ! kubectl -n rook-ceph get secret rook-ceph-dashboard-password &>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done

    logSuccess "Rook deployed"
}

maybeDefaultRookStorageClass() {
    # different versions of Rook have different storage class specs so never re-apply
    if ! kubectl get storageclass | grep -q rook.io ; then
        storageClassDeploy
        return
    fi

    if ! defaultStorageClassExists ; then
        logSubstep "making existing rook storage class default"
        kubectl patch storageclass "$STORAGE_CLASS" -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    fi
}

defaultStorageClassExists() {
    kubectl get storageclass -o=jsonpath='{.items[*].metadata.annotations}' | grep -q "storageclass.kubernetes.io/is-default-class":"true"
}

storageClassDeploy() {
	render_yaml "rook-ceph-storage-class.yaml" > /tmp/rook-ceph-storage-class.yaml
    kubectl apply -f /tmp/rook-ceph-storage-class.yaml
}

spinnerRookReady()
{
    logStep "Await rook ready"
    spinnerPodRunning rook-ceph rook-ceph-operator
    spinnerPodRunning rook-ceph rook-ceph-agent
    spinnerPodRunning rook-ceph rook-discover
    spinnerRookFlexVolumePluginReady
    logSuccess "Rook Ready!"
}

#######################################
# Spinner Rook FlexVolume plugin ready
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
spinnerRookFlexVolumePluginReady()
{
    local delay=0.75
    local spinstr='|/-\'
    while [ ! -e /usr/libexec/kubernetes/kubelet-plugins/volume/exec/ceph.rook.io~rook-ceph/rook-ceph ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

isRook1()
{
    kubectl -n rook-ceph get cephblockpools replicapool &>/dev/null
}
