#!/bin/bash

export K0S_VERSION

function discover_k0s_version() {
    if [ -z "$K0S_VERSION" ]; then
        K0S_VERSION=$(curl -sSLf "https://docs.k0sproject.io/stable.txt")
    fi

    local major=, minor=, patch=
    semverParse "${K0S_VERSION#v}"
    export KUBERNETES_VERSION="${K0S_VERSION#v}" # trim v prefix
    export KUBERNETES_TARGET_VERSION_MAJOR="$major"
    export KUBERNETES_TARGET_VERSION_MINOR="$minor"
    export KUBERNETES_TARGET_VERSION_PATCH="$patch"
}

function report_k0s_install() {
    logStep "K0s $K0S_VERSION"

    report_addon_start "k0s" "$K0S_VERSION"
    export REPORTING_CONTEXT_INFO="k0s $K0S_VERSION"

    # check if k0s is already installed at the correct version
    if [ "$(k0s version)" != "$K0S_VERSION" ]; then
        k0s_upgrade
    fi

    k0s_configure_controller
    k0s_install_controller
    k0s_wait_for_ready
    k0s_kubeconfig

    wait_for_nodes
    # kurl should really use node-role.kubernetes.io/control-plane to identify control plane nodes
    kubectl label --overwrite node "$(get_local_node_name)" node-role.kubernetes.io/master=

    export REPORTING_CONTEXT_INFO=""
    report_addon_success "k0s" "$K0S_VERSION"

    logSuccess "K0s $K0S_VERSION installed successfully"
}

function report_k0s_join_controller() {
    local join_token="$1"

    K0S_VERSION="$KUBERNETES_VERSION"
    [[ $K0S_VERSION == v* ]] || K0S_VERSION="v$K0S_VERSION" # add v prefix if missing

    logStep "K0s $K0S_VERSION"

    report_addon_start "k0s-join-controller" "$K0S_VERSION"
    export REPORTING_CONTEXT_INFO="k0s-join-controller $K0S_VERSION"

    # check if k0s is already installed at the correct version
    if [ "$(k0s version)" != "$K0S_VERSION" ]; then
        k0s_upgrade
    fi

    k0s_configure_controller
    k0s_join_controller "$join_token"
    k0s_wait_for_ready
    k0s_kubeconfig

    wait_for_nodes
    # kurl should really use node-role.kubernetes.io/control-plane to identify control plane nodes
    kubectl label --overwrite node "$(get_local_node_name)" node-role.kubernetes.io/master=

    export REPORTING_CONTEXT_INFO=""
    report_addon_success "k0s-join-controller" "$K0S_VERSION"

    logSuccess "K0s $K0S_VERSION installed successfully"
}

function report_k0s_join_worker() {
    local join_token="$1"

    K0S_VERSION="$KUBERNETES_VERSION"
    [[ $K0S_VERSION == v* ]] || K0S_VERSION="v$K0S_VERSION" # add v prefix if missing

    logStep "K0s $K0S_VERSION"

    report_addon_start "k0s-join-worker" "$K0S_VERSION"
    export REPORTING_CONTEXT_INFO="k0s-join-worker $K0S_VERSION"

    # check if k0s is already installed at the correct version
    if [ "$(k0s version)" != "$K0S_VERSION" ]; then
        k0s_upgrade
    fi

    k0s_join_worker "$join_token"
    k0s_wait_for_ready

    export REPORTING_CONTEXT_INFO=""
    report_addon_success "k0s-join-worker" "$K0S_VERSION"

    logSuccess "K0s $K0S_VERSION installed successfully"
}

function k0s_maybe_download() {
    # check if k0s is not already installed
    if ! commandExists "k0s" ; then
        k0s_download
    fi
}

function k0s_download() {
    curl -sSLf https://get.k0s.sh | sh
}

function k0s_upgrade() {
    local is_healthy=0
    if k0s_api_is_healthy ; then
        is_healthy=1
    fi
    k0s stop || true
    k0s_download
    if [ "$is_healthy" = "1" ] ; then
        k0s start
        k0s_wait_for_ready
    fi
}

function k0s_configure_controller() {
    # NOTE: this will not reconcile on re-running the script
    if [ ! -f "$DIR"/kustomize/k0s/controller/k0s.yaml ]; then
        k0s config create > "$DIR"/kustomize/k0s/controller/k0s.yaml
    fi

    # hack to get k0s kubectl to work prior to installing
    local kubeconfig=
    kubeconfig="$(k0s_get_kubeconfig)"
    if [ ! -f "$kubeconfig" ]; then
        mkdir -p "$(dirname "$kubeconfig")"
        touch "$kubeconfig"
    fi

    mkdir -p /etc/k0s/
    k0s kubectl kustomize "$DIR"/kustomize/k0s/controller/ > /etc/k0s/k0s.yaml
}

function k0s_install_controller() {
    if k0s status >/dev/null 2>&1 ; then
        return
    fi
    # this command will fail if k0s is already installed
    ( set -x; k0s install controller --enable-worker --no-taints -c /etc/k0s/k0s.yaml ) || true
    k0s start
}

function k0s_join_controller() {
    local join_token="$1"

    if k0s status >/dev/null 2>&1 ; then
        return
    fi
    # this command will fail if k0s is already installed
    ( set -x; k0s install controller --enable-worker --no-taints --token-file "$join_token" -c /etc/k0s/k0s.yaml ) || true
    k0s start
}

function k0s_join_worker() {
    local join_token="$1"

    if k0s status >/dev/null 2>&1 ; then
        return
    fi
    # this command will fail if k0s is already installed
    ( set -x; k0s install worker --token-file "$join_token" ) || true
    k0s start
}

function k0s_kubectl() {
    if ! commandExists "kubectl" ; then
        # quick and dirty way to get kubectl in the path
        # TODO: make this better
        cat > /usr/local/bin/kubectl <<"EOF"
#!/bin/sh
set -e
k0s kubectl "$@"
EOF
        chmod +x /usr/local/bin/kubectl
    fi
}

function k0s_ctr() {
    if ! commandExists "ctr" ; then
        # quick and dirty way to get ctr in the path
        # TODO: make this better
        cat > /usr/local/bin/ctr <<"EOF"
#!/bin/sh
set -e
# strips namespace and address flags from ctr command
next=0
for arg do
  shift
  [ "$next" = "1" ] && next=0 && continue
  ( [ "$arg" = "-n" ] || [ "$arg" = "--namespace" ] || [ "$arg" = "-a" ] || [ "$arg" = "--address" ] ) && next=1 && continue
  ( [[ $arg = -n=* ]] || [[ $arg = --namespace=* ]] || [[ $arg = -a=* ]] || [[ $arg = --address=* ]] ) && continue
  set -- "$@" "$arg"
done
k0s ctr "$@"
EOF
        chmod +x /usr/local/bin/ctr
    fi
}

function k0s_kubeconfig() {
    export KUBECONFIG=~/.kube/config

    mkdir -p "$HOME/.kube"
    k0s kubeconfig admin > "$HOME/.kube/config"

    if [ -n "$SUDO_UID" ] && [ "$ID" != "$SUDO_UID" ]; then
        local home=
        home="$(eval echo "~$(id -un $SUDO_UID)")"
        mkdir -p "$home/.kube"
        k0s kubeconfig admin > "$HOME/.kube/config"
    fi
}

function k0s_wait_for_ready() {
    spinner_until 300 k0s_api_is_healthy
    spinner_until 60 k0s_api_is_healthy # wait for two in a row
}

function k0s_containerd_configure() {
    if ! commandExists registry_init ; then
        return
    fi

    registry_init
    
    k0s_registry_containerd_configure "$DOCKER_REGISTRY_IP"

    if [ "$CONTAINERD_NEEDS_RESTART" = "1" ]; then
        k0s_restart
    fi
}

function k0s_restart() {
    # restart containerd to pick up new config
    k0s stop || true
    k0s start
    k0s_wait_for_ready
}

function main_install_k0s() {
    # yaml_airgap
    # proxy_bootstrap
    download_util_binaries
    get_machine_id
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    export MASTER=1 # parse_yaml_into_bash_variables will unset master
    export HA_CLUSTER=1
    prompt_license

    # is_ha
    # parse_kubernetes_target_version
    discover full-cluster
    report_install_start
    trap ctrl_c SIGINT # trap ctrl+c (SIGINT) and handle it by reporting that the user exited intentionally (along with the line/version/etc)
    trap trap_report_error ERR # trap errors and handle it by reporting the error line and parent function
    # preflights
    # common_prompts
    journald_persistent
    # configure_proxy
    # configure_no_proxy_preinstall
    discover_k0s_version
    k0s_maybe_download
    k0s_kubectl
    k0s_ctr
    "${K8S_DISTRO}_addon_for_each" addon_fetch
    # if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then
    #     host_preflights "1" "0" "0"
    # else
    #     host_preflights "1" "0" "1"
    # fi
    install_host_dependencies
    get_common
    # setup_kubeadm_kustomize
    # rook_upgrade_maybe_report_upgrade_rook
    "${K8S_DISTRO}_addon_for_each" addon_pre_init
    # discover_pod_subnet
    # discover_service_subnet
    # configure_no_proxy
    # install_cri
    get_shared
    # report_upgrade_kubernetes
    report_k0s_install
    kubectl get ns kurl >/dev/null 2>&1 || kubectl create ns kurl --save-config
    k0s_containerd_configure
    export SUPPORT_BUNDLE_READY=1 # allow ctrl+c and ERR traps to collect support bundles now that k8s is installed
    kurl_init_config
    "${K8S_DISTRO}_addon_for_each" addon_install
    # maybe_cleanup_rook
    # maybe_cleanup_longhorn
    # helmfile_sync
    kurl_config
    # uninstall_docker
    "${K8S_DISTRO}_addon_for_each" addon_post_init
    outro
    package_cleanup

    report_install_success
}

function main_join_k0s() {
    # proxy_bootstrap
    download_util_binaries
    get_machine_id
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    export HA_CLUSTER=1
    prompt_license
    # parse_kubernetes_target_version
    discover
    # preflights
    # join_prompts
    # join_preflights # must come after joinPrompts as this function requires API_SERVICE_ADDRESS
    # common_prompts
    journald_persistent
    # configure_proxy
    # configure_no_proxy
    discover_k0s_version
    k0s_maybe_download
    k0s_kubectl
    k0s_ctr
    "${K8S_DISTRO}_addon_for_each" addon_fetch
    # host_preflights "${MASTER:-0}" "1" "0"
    install_host_dependencies
    get_common
    # setup_kubeadm_kustomize
    # install_cri
    get_shared
    "${K8S_DISTRO}_addon_for_each" addon_join
    # helm_load
    # kubernetes_host
    # install_helm

    local tmpfile
    tmpfile=$(mktemp --suffix=-join-token)
    echo "$KUBEADM_TOKEN" > "$tmpfile"
    if [ "$MASTER" = "1" ]; then
        report_k0s_join_controller "$tmpfile"
    else
        report_k0s_join_worker "$tmpfile"
    fi
    outro
    package_cleanup
}
