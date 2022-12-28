function longhorn_host_init_common() {
    longhorn_install_iscsi_if_missing_common $1
    longhorn_install_nfs_utils_if_missing_common $1
    mkdir -p /var/lib/longhorn
    chmod 700 /var/lib/longhorn
}

function longhorn_install_iscsi_if_missing_common() {
    local src=$1

    if ! systemctl list-units | grep -q iscsid ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" open-iscsi
                ;;

            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" iscsi-initiator-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active iscsid; then
        systemctl start iscsid
    fi

    if ! systemctl -q is-enabled iscsid; then
        systemctl enable iscsid
    fi
}

function longhorn_install_nfs_utils_if_missing_common() {
    local src=$1

    if ! systemctl list-units | grep -q nfs-utils ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" nfs-common
                ;;

            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" nfs-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active nfs-utils; then
        systemctl start nfs-utils
    fi

    if ! systemctl -q is-enabled nfs-utils; then
        systemctl enable nfs-utils
    fi
}

# scale down prometheus, move all 'longhorn' PVCs to provided storage class, scale up prometheus
# Supported storage class migrations from longhorn are: 'rook' and 'openebs'
function longhorn_to_sc_migration() {
    local destStorageClass=$1
    local didRunValidationChecks=$2
    local scProvisioner
    scProvisioner=$(kubectl get sc "$destStorageClass" -ojsonpath='{.provisioner}')

    # we only support migrating to 'rook' and 'openebs' storage classes
    if [[ "$scProvisioner" != *"rook"* ]] && [[ "$scProvisioner" != *"openebs"* ]]; then
        bail "Longhorn to $scProvisioner migration is not supported"
    fi

    report_addon_start "longhorn-to-${scProvisioner}-migration" "v1"

    # set prometheus scale if it exists
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl -n monitoring get prometheus k8s &>/dev/null; then
            # before scaling down prometheus, scale down ekco as it will otherwise restore the prometheus scale
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                kubectl -n kurl scale deploy ekc-operator --replicas=0
                echo "Waiting for ekco pods to be removed"
                spinner_until 120 ekco_pods_gone
            fi

            kubectl -n monitoring patch prometheus k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 0}]'
            echo "Waiting for prometheus pods to be removed"
            spinner_until 120 prometheus_pods_gone
        fi
    fi

    # get the list of StorageClasses that use Longhorn
    longhorn_scs=$(kubectl get storageclass | grep longhorn | grep -v '(default)' | awk '{ print $1}') # any non-default longhorn StorageClasses
    longhorn_default_sc=$(kubectl get storageclass | grep longhorn | grep '(default)' | awk '{ print $1}') # any default longhorn StorageClasses

    for longhorn_sc in $longhorn_scs
    do
        if [ "$didRunValidationChecks" == "1" ]; then
            # run the migration w/o validation checks
            $BIN_PVMIGRATE --source-sc "$longhorn_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --skip-free-space-check --skip-preflight-validation
        else
            # run the migration (without setting defaults)
            $BIN_PVMIGRATE --source-sc "$longhorn_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE"
        fi
    done

    for longhorn_sc in $longhorn_default_sc
    do
        if [ "$didRunValidationChecks" == "1" ]; then
            # run the migration w/o validation checks
            $BIN_PVMIGRATE --source-sc "$longhorn_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --skip-free-space-check --skip-preflight-validation --set-defaults
        else
            # run the migration (setting defaults)
            $BIN_PVMIGRATE --source-sc "$longhorn_sc" --dest-sc "$destStorageClass" --rsync-image "$KURL_UTIL_IMAGE" --set-defaults
        fi
    done

    # reset prometheus (and ekco) scale
    if kubectl get namespace monitoring &>/dev/null; then
        if kubectl get prometheus -n monitoring k8s &>/dev/null; then
            if kubernetes_resource_exists kurl deployment ekc-operator; then
                kubectl -n kurl scale deploy ekc-operator --replicas=1
            fi

            kubectl patch prometheus -n monitoring  k8s --type='json' --patch '[{"op": "replace", "path": "/spec/replicas", value: 2}]'
        fi
    fi

    # print success message
    printf "${GREEN}Migration from longhorn to %s completed successfully!\n${NC}" "$scProvisioner"
    report_addon_success "longhorn-to-$scProvisioner-migration" "v1"
}

# if PVCs and object store data have both been migrated from longhorn and longhorn is no longer specified in the kURL spec, remove longhorn
function maybe_cleanup_longhorn() {
    if [ -z "$LONGHORN_VERSION" ]; then
        if [ "$DID_MIGRATE_LONGHORN_PVCS" == "1" ]; then
            report_addon_start "longhorn-removal" "v1"
            remove_longhorn
            report_addon_success "longhorn-removal" "v1"
        fi
    fi
}

# longhorn_pvs_removed returns true when we can't find any pv using the longhorn csi driver.
function longhorn_pvs_removed() {
    local pvs
    pvs=$(kubectl get pv -o=jsonpath='{.items[*].spec.csi.driver}' | grep "longhorn" | wc -l)
    [ "$pvs" = "0" ]
}

# remove_longhorn deletes everything longhorn releated: deployments, CR objects, and CRDs.
function remove_longhorn() {
    # make sure there aren't any PVs using longhorn before deleting it
    echo "Waiting for Longhorn PVs to be removed"
    if ! spinner_until 60 longhorn_pvs_removed; then
        # sometimes longhorn hangs and we need to restart kubelet to make it work again, we
        # are going to give this approach a try here before bailing out.
        printf "${YELLOW}Some Longhorn PVs are still online, trying to restart kubelet.\n${NC}"
        systemctl restart kubelet
        echo "Waiting for Longhorn PVs to be removed"
        if ! spinner_until 60 longhorn_pvs_removed; then
            printf "%b" "$RED"
            printf "ERROR: \n"
            printf "There are still PVs using Longhorn.\n"
            printf "Remove these PVs before continuing.\n"
            printf "%b" "$NC"
            exit 1
        fi
    fi

    # scale ekco to 0 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=0
        echo "Waiting for ekco pods to be removed"
        spinner_until 120 ekco_pods_gone
    fi

    # remove longhorn volumes first so the operator can correctly delete them.
    printf "Removing Longhorn volumes:\n"
    kubectl delete volumes.longhorn.io -n longhorn-system --all

    # once volumes have been gone we can remove all other longhorn CR objects.
    printf "Removing Longhorn custom resource objects - this may take some time:\n"
    kubectl get crd | grep 'longhorn' | grep -v 'volumes' | awk '{ print $1 }' | xargs -I'{}' kubectl -n longhorn-system delete '{}' --all

    # delete longhorn CRDs
    printf "Removing Longhorn custom resources:\n"
    kubectl get crd | grep 'longhorn' | awk '{ print $1 }' | xargs -I'{}' kubectl delete crd '{}'

    # delete longhorn ns
    kubectl delete ns longhorn-system

    # delete longhorn storageclass(es)
    printf "Removing Longhorn StorageClasses"
    kubectl get storageclass | grep longhorn | awk '{ print $1 }' | xargs -I'{}' kubectl delete storageclass '{}'

    # scale ekco back to 1 replicas if it exists
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi

    # print success message
    printf "%bRemoved Longhorn successfully!\n%b" "$GREEN" "$NC"
}
