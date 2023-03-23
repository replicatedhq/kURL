# shellcheck disable=SC2148

export SKIP_LONGHORN_INSTALL
export DID_MIGRATE_ROOK_PVCS
export LONGHORN_IS_DEFAULT_STORAGECLASS

function longhorn_pre_init() {
    if [ -z "$LONGHORN_UI_BIND_PORT" ]; then
        LONGHORN_UI_BIND_PORT="30880"
    fi
    if [ -z "$LONGHORN_UI_REPLICA_COUNT" ]; then
        LONGHORN_UI_REPLICA_COUNT="0"
    fi

    # Error check that someone didn't add the percent sign to this integer
    local re='^[0-9]+$'
    if [ -n "$LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE" ] && ! [[ $LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE =~ $re ]]; then
        bail "You entered ${LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE} for LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE, but it must be an integer. e.g. 200"
    fi
    if [ -z "$LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE" ]; then
        LONGHORN_STORAGE_OVER_PROVISIONING_PERCENTAGE="200"
    fi

    # Can only upgrade 1 minor version at a time
    if ! longhorn_can_upgrade ; then
        printf "${YELLOW}Continue without upgrading longhorn? ${NC}"
        if ! confirmY ; then
            bail "Please upgrade to the previous minor version first."
        fi
        SKIP_LONGHORN_INSTALL=1
    fi

    longhorn_host_init_common "$DIR/addons/longhorn/$LONGHORN_VERSION"
}

function longhorn() {
    if [ "$SKIP_LONGHORN_INSTALL" = "1" ]; then
        local current_version
        current_version=$(longhorn_current_version)
        echo "Longhorn $current_version is already installed, will not upgrade to ${LONGHORN_VERSION}"
        return 0
    fi

    local src="$DIR/addons/longhorn/$LONGHORN_VERSION"
    local dst="$DIR/kustomize/longhorn"

    cp -r "$src/yaml" "$dst/yaml"
    cp "$src/crds.yaml" "$dst/"

    if longhorn_has_default_storageclass && ! longhorn_is_default_storageclass ; then
        logWarn "Existing default storage class that is not Longhorn detected"
        logWarn "Longhorn will still be installed as the non-default storage class."
        LONGHORN_IS_DEFAULT_STORAGECLASS=false
    else
        echo "Longhorn will be installed as the default storage class"
        LONGHORN_IS_DEFAULT_STORAGECLASS=true
    fi
    render_yaml_file_2 "$src/template/storageclass.yaml" > "$dst/yaml/storageclass.yaml"

    longhorn_check_mount_propagation "$src" "$dst"

    render_yaml_file_2 "$src/template/patch-ui-service.yaml" > "$dst/yaml/patch-ui-service.yaml"
    render_yaml_file_2 "$src/template/patch-ui-deployment.yaml" > "$dst/yaml/patch-ui-deployment.yaml"
    render_yaml_file_2 "$src/template/patch-defaults-cm.yaml" > "$dst/yaml/patch-defaults-cm.yaml"

    kubectl apply -f "$dst/crds.yaml"
    echo "Waiting for Longhorn CRDs to be created"
    spinner_until 120 kubernetes_resource_exists default crd engines.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd replicas.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd settings.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd volumes.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd engineimages.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd nodes.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd instancemanagers.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd sharemanagers.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd backingimages.longhorn.io
    spinner_until 120 kubernetes_resource_exists default crd backingimagemanagers.longhorn.io

    kubectl apply -k "$dst/yaml/"

    echo "Waiting for Longhorn Manager to create Storage Class"
    if ! spinner_until 120 kubernetes_resource_exists longhorn-system sc longhorn ; then
        bail "Longhorn Manager failed to create Storage Class"
    fi

    echo "Checking if all nodes have Longhorn Manager Daemonset prerequisites"
    longhorn_maybe_init_hosts

    echo "Waiting for Longhorn Manager Daemonset to be ready"
    spinner_until 180 longhorn_daemonset_is_ready longhorn-manager

    longhorn_maybe_migrate_from_rook
}

function longhorn_is_default_storageclass() {
    if kubectl get sc longhorn &> /dev/null && \
    [ "$(kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" = "true" ]; then
        return 0
    fi
    return 1
}

function longhorn_has_default_storageclass() {
    if kubectl get sc -o jsonpath='{.items[*].metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q "true" ; then
        return 0
    fi
    return 1
}

function longhorn_daemonset_is_ready() {
    local dsname=$1
    local desired=
    local ready=
    desired=$(kubectl get daemonsets -n longhorn-system "$dsname" --no-headers | tr -s ' ' | cut -d ' ' -f2)
    ready=$(kubectl get daemonsets -n longhorn-system "$dsname" --no-headers | tr -s ' ' | cut -d ' ' -f4)

    if [ "$desired" = "$ready" ] && [ -n "$desired" ] && [ "$desired" != "0" ]; then
        return 0
    fi
    return 1
}

function longhorn_join() {
    longhorn_host_init_common "$DIR/addons/longhorn/$LONGHORN_VERSION"
}

function longhorn_check_mount_propagation() {
    local src=$1
    local dst=$2

    kubectl get ns longhorn-system >/dev/null 2>&1 || kubectl create ns longhorn-system >/dev/null 2>&1
    kubectl delete -n longhorn-system ds longhorn-environment-check 2>/dev/null || true

    render_yaml_file "$src/template/mount-propagation.yaml" > "$dst/yaml/mount-propagation.yaml"
    kubectl apply -f "$dst/yaml/mount-propagation.yaml"
    echo "Waiting for the Longhorn Mount Propagation Check Daemonset to be ready"
    spinner_until 120 longhorn_daemonset_is_ready longhorn-environment-check

    longhorn_validate_ds

    kubectl delete -f "$dst/yaml/mount-propagation.yaml"
}

# pass if at least one node will support longhorn, but with a warning if there are nodes that won't
# only fail if there is no chance that longhorn will work on any nodes, as installations may have dedicated 'storage' vs 'not-storage' nodes
function longhorn_validate_ds() {
    local allpods=
    local bidirectional=
    allpods=$(kubectl get daemonsets -n longhorn-system longhorn-environment-check --no-headers | tr -s ' ' | cut -d ' ' -f4)
    bidirectional=$(kubectl get pods -n longhorn-system -l app=longhorn-environment-check -o=jsonpath='{.items[*].spec.containers[0].volumeMounts[*]}' | grep -o 'Bidirectional' | wc -l)

    if [ "$allpods" == "" ] || [ "$allpods" -eq "0" ]; then
        logWarn "unable to determine health and status of longhorn-environment-check daemonset"
    else
        if [ "$bidirectional" -lt "$allpods" ]; then
            logWarn "Only $bidirectional of $allpods nodes support Longhorn storage"
        else
            echo "All nodes support bidirectional mount propagation"
        fi

        if [ "$bidirectional" -eq "0" ]; then
            bail "No nodes with mount propagation enabled detected - Longhorn will not work. See https://longhorn.io/docs/1.1.1/deploy/install/#installation-requirements for details"
        fi
    fi
}

# if this is a multinode cluster, we need to prepare all hosts to run the daemonset
function longhorn_maybe_init_hosts() {
    while true; do
        local desired=
        local ready=
        desired=$(kubectl get daemonsets -n longhorn-system longhorn-manager --no-headers | tr -s ' ' | cut -d ' ' -f2)
        ready=$(kubectl get daemonsets -n longhorn-system longhorn-manager --no-headers | tr -s ' ' | cut -d ' ' -f4)

        if [ "$desired" = "$ready" ] && [ -n "$desired" ] && [ "$desired" -ge "1" ]; then
            return
        fi

        while read -r pod_name; do
            if kubectl -n longhorn-system logs -p "$pod_name" | grep -q 'please make sure you have iscsiadm/open-iscsi installed on the host'; then
                printf "\nRun this script on all nodes to install Longhorn prerequisites:\n"
                if [ "$AIRGAP" = "1" ]; then
                    printf "\n\t${GREEN}cat ./tasks.sh | sudo bash -s longhorn-node-initilize airgap${NC}\n\n"
                else
                    local prefix=
                    prefix="$(build_installer_prefix "${INSTALLER_ID}" "${KURL_VERSION}" "${KURL_URL}" "${PROXY_ADDRESS}")"
                    printf "\n\t${GREEN}${prefix}tasks.sh | sudo bash -s longhorn-node-initilize${NC}\n\n"
                fi

                if ! prompts_can_prompt ; then
                    logWarn "Install Longhorn prerequisites prompt explicitly ignored"
                    return
                fi

                while true; do
                    echo ""
                    printf "Has the command been ran on all remote nodes? "
                    if confirmN ; then
                        return
                    else
                        bail "Migration to Longhorn has been aborted."
                    fi
                done
            fi
        done < <(kubectl -n longhorn-system get pods -l app=longhorn-manager --no-headers | grep -v Running | awk '{print $1}')

        sleep 1
    done
}

# if rook-ceph is installed but is not specified in the kURL spec, migrate data from rook-ceph to longhorn
function longhorn_maybe_migrate_from_rook() {
    # check that OPENEBS_VERSION is empty as we prefer to migrate to openebs if it is installed
    if [ -z "$ROOK_VERSION" ] && [ -z "$OPENEBS_VERSION" ]; then
        if kubectl get ns | grep -q rook-ceph; then
            rook_ceph_to_sc_migration "longhorn"
            # used to automatically delete rook-ceph if object store data was also migrated
            add_rook_pvc_migration_status
        fi
    fi
}

# do not upgrade more than one minor version at a time
function longhorn_can_upgrade() {
    local current_version=
    current_version="$(longhorn_current_version)"

    if [ -z "$current_version" ]; then
        return 0
    fi

    semverParse "${current_version}"
    # shellcheck disable=SC2154
    local current_version_minor="${minor}"

    semverParse "${LONGHORN_VERSION}"
    local next_version_minor="${minor}"

    local previous_version_minor="$((next_version_minor-1))"

    if [ "$current_version_minor" -lt "$previous_version_minor" ]; then
        logWarn "Upgrades to Longhorn version ${LONGHORN_VERSION} from versions prior to 1.${previous_version_minor}.x are unsupported."
        logWarn "Individual upgrades from one version to the next are required for upgrading multiple minor versions"
        return 1
    fi
    return 0
}

function longhorn_current_version() {
    kubectl -n longhorn-system get daemonset longhorn-manager 2>/dev/null \
        -o jsonpath='{.spec.template.spec.containers[0].image}' \
        | awk -F':' 'NR==1 { print $2 }' \
        | sed 's/v\([^-]*\).*/\1/'
}
