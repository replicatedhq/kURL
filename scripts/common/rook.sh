
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

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_system_yaml=1 > /tmp/rook-ceph-system.yml
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS rook_cluster_yaml=1 > /tmp/rook-ceph.yml

    kubectl apply -f /tmp/rook-ceph-system.yml

    spinnerRookReady # creating the cluster before the operator is ready fails

    kubectl apply -f /tmp/rook-ceph.yml
    storageClassDeploy
 
    # wait for ceph dashboard password to be generated
    if [ "$rook08" = "0" ]; then
        local delay=0.75
        local spinstr='|/-\'
        while ! kubectl -n rook-ceph get secret rook-ceph-dashboard-password &>/dev/null; do
            local temp=${spinstr#?}
            printf " [%c]  " "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep $delay
            printf "\b\b\b\b\b\b"
        done
    fi

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

storageClassDeploy() {
    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS storage_class_yaml=1 > /tmp/storage-class.yml
    kubectl apply -f /tmp/storage-class.yml
}
