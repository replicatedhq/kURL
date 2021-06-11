
function preflights() {
    require64Bit
    bailIfUnsupportedOS
    mustSwapoff
    bail_if_docker_unsupported_os
    checkDockerK8sVersion
    checkFirewalld
    checkUFW
    must_disable_selinux
    apply_iptables_config
    cri_preflights
    kotsadm_prerelease
    host_nameservers_reachable

    return 0
}

function join_preflights() {
    preflights_require_no_kubernetes_or_current_node

    return 0
}

function require_root_user() {
    local user="$(id -un 2>/dev/null || true)"
    if [ "$user" != "root" ]; then
        bail "Error: this installer needs to be run as root."
    fi
}


function require64Bit() {
    case "$(uname -m)" in
        *64)
            ;;
        *)
            echo >&2 'Error: you are not using a 64bit platform.'
            echo >&2 'This installer currently only supports 64bit platforms.'
            exit 1
            ;;
    esac
}

function bailIfUnsupportedOS() {
    case "$LSB_DIST$DIST_VERSION" in
        ubuntu16.04|ubuntu18.04|ubuntu20.04)
            ;;
        rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8|rhel7.9|rhel8.0|rhel8.1|rhel8.2|rhel8.3)
            ;;
        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|centos7.9|centos8.0|centos8.1|centos8.2|centos8.3)
            ;;
        amzn2)
            ;;
        ol7.4|ol7.5|ol7.6|ol7.7|ol7.8|ol7.9|ol8.0|ol8.1|ol8.2|ol8.3|ol8.4)
            ;;
        *)
            bail "Kubernetes install is not supported on ${LSB_DIST} ${DIST_VERSION}"
            ;;
    esac
}
 
function mustSwapoff() {
    if swap_is_on || swap_is_enabled; then
        printf "\n${YELLOW}This application is incompatible with memory swapping enabled. Disable swap to continue?${NC} "
        if confirmY ; then
            printf "=> Running swapoff --all\n"
            swapoff --all
            if swap_fstab_enabled; then
                swap_fstab_disable
            fi
            if swap_service_enabled; then
                swap_service_disable
            fi
            if swap_azure_linux_agent_enabled; then
                swap_azure_linux_agent_disable
            fi
            logSuccess "Swap disabled.\n"
        else
            bail "\nDisable swap with swapoff --all and remove all swap entries from /etc/fstab before re-running this script"
        fi
    fi
}

function swap_is_on() {
   swapon --summary | grep --quiet " " # todo this could be more specific, swapon -s returns nothing if its off
}

function swap_is_enabled() {
    swap_fstab_enabled || swap_service_enabled || swap_azure_linux_agent_enabled
}

function swap_fstab_enabled() {
    cat /etc/fstab | grep --quiet --ignore-case --extended-regexp '^[^#]+swap'
}

function swap_fstab_disable() {
    printf "=> Commenting swap entries in /etc/fstab \n"
    sed --in-place=.bak '/\bswap\b/ s/^/#/' /etc/fstab
    printf "=> A backup of /etc/fstab has been made at /etc/fstab.bak\n\n"
    printf "\n${YELLOW}Changes have been made to /etc/fstab. We recommend reviewing them after completing this installation to ensure mounts are correctly configured.${NC}\n\n"
    sleep 5 # for emphasis of the above ^
}

# This is a service on some Azure VMs that just enables swap
function swap_service_enabled() {
    systemctl -q is-enabled temp-disk-swapfile 2>/dev/null
}

function swap_service_disable() {
    printf "=> Disabling temp-disk-swapfile service\n"
    systemctl disable temp-disk-swapfile
}

function swap_azure_linux_agent_enabled() {
    cat /etc/waagent.conf 2>/dev/null | grep -q 'ResourceDisk.EnableSwap=y'
}

function swap_azure_linux_agent_disable() {
    printf "=> Disabling swap in Azure Linux Agent configuration file /etc/waagent.conf\n"
    sed -i 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/g' /etc/waagent.conf
}


checkDockerK8sVersion()
{
    getDockerVersion
    if [ -z "$DOCKER_VERSION" ]; then
        return
    fi

    case "$KUBERNETES_TARGET_VERSION_MINOR" in 
        14|15)
            compareDockerVersions "$DOCKER_VERSION" 1.13.1
            if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
                bail "Minimum Docker version for Kubernetes $KUBERNETES_VERSION is 1.13.1."
            fi
            ;;
    esac
}

function bail_if_docker_unsupported_os() {
    if is_docker_version_supported ; then
        return
    fi

    if commandExists "docker" ; then
        return
    fi

    bail "Docker ${DOCKER_VERSION} is not supported on ${LSB_DIST} ${DIST_VERSION}"
}

function is_docker_version_supported() {
    case "$LSB_DIST" in
    centos|rhel)
        ;;
    *)
        return 0
        ;;
    esac
    if [ "$DOCKER_VERSION" = "18.09.8" ] || [ "$DOCKER_VERSION" = "19.03.4" ] || [ "$DOCKER_VERSION" = "19.03.10" ]; then
        return 1
    fi
    return 0
}

checkFirewalld() {
    if [ -n "$PRESERVE_DOCKER_CONFIG" ]; then
        return
    fi

    apply_firewalld_config

    if [ "$BYPASS_FIREWALLD_WARNING" = "1" ]; then
        return
    fi
    if ! systemctl -q is-active firewalld ; then
        return
    fi

    if [ "$HARD_FAIL_ON_FIREWALLD" = "1" ]; then
        printf "${RED}Firewalld is active${NC}\n" 1>&2
        exit 1
    fi

    if [ -n "$DISABLE_FIREWALLD" ]; then
        systemctl stop firewalld
        systemctl disable firewalld
        return
    fi
   
    printf "${YELLOW}Firewalld is active, please press Y to disable ${NC}"
    if confirmY ; then
        systemctl stop firewalld
        systemctl disable firewalld
        return
    fi

    printf "${YELLOW}Continue with firewalld active? ${NC}"
    if confirmN ; then
        BYPASS_FIREWALLD_WARNING=1
        return
    fi
    exit 1
}

checkUFW() {
    if [ -n "$PRESERVE_DOCKER_CONFIG" ]; then
        return
    fi

    if [ "$BYPASS_UFW_WARNING" = "1" ]; then
        return
    fi

    # check if UFW is enabled and installed in systemctl
    if ! systemctl -q is-active ufw ; then
        return
    fi

    # check if UFW is active/inactive
    UFW_STATUS=$(ufw status | grep 'Status: ' | awk '{ print $2 }')
    if [ "$UFW_STATUS" = "inactive" ]; then
      return
    fi

    if [ "$HARD_FAIL_ON_UFW" = "1" ]; then
        printf "${RED}UFW is active${NC}\n" 1>&2
        exit 1
    fi

    if [ -n "$DISABLE_UFW" ]; then
        ufw disable
        return
    fi

    printf "${YELLOW}UFW is active, please press Y to disable ${NC}"
    if confirmY ; then
        ufw disable
        return
    fi

    printf "${YELLOW}Continue with ufw active? ${NC}"
    if confirmN ; then
        BYPASS_UFW_WARNING=1
        return
    fi
    exit 1
}

must_disable_selinux() {
    # From kubernets kubeadm docs for RHEL:
    #
    #    Disabling SELinux by running setenforce 0 is required to allow containers to
    #    access the host filesystem, which is required by pod networks for example.
    #    You have to do this until SELinux support is improved in the kubelet.

    # Check and apply YAML overrides
    if [ -n "$PRESERVE_SELINUX_CONFIG" ]; then
        return
    fi

    apply_selinux_config
    if [ -n "$BYPASS_SELINUX_PREFLIGHT" ]; then
        return
    fi

    if selinux_enabled && selinux_enforced ; then
        if [ -n "$DISABLE_SELINUX" ]; then
            setenforce 0
            sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config
            return
        fi

        printf "\n${YELLOW}Kubernetes is incompatible with SELinux. Disable SELinux to continue?${NC} "
        if confirmY ; then
            setenforce 0
            sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config
        else
            bail "\nDisable SELinux with 'setenforce 0' before re-running install script"
        fi
    fi
}

function force_docker() {
    DOCKER_VERSION="19.03.4"
    echo "NO CRI version was listed in yaml or found on host OS, defaulting to online docker install"
    echo "THIS FEATURE IS NOT SUPPORTED AND WILL BE DEPRECATED IN FUTURE KURL VERSIONS"
}

function cri_preflights() {
    require_cri
}

function require_cri() {
    if commandExists docker ; then
        SKIP_DOCKER_INSTALL=1
        return 0
    fi

    if commandExists ctr ; then
        return 0
    fi

    if [ "$LSB_DIST" = "rhel" ]; then
        if [ -n "$NO_CE_ON_EE" ]; then
            printf "${RED}Enterprise Linux distributions require Docker Enterprise Edition. Please install Docker before running this installation script.${NC}\n" 1>&2
            return 0
        fi
    fi

    if [ "$SKIP_DOCKER_INSTALL" = "1" ]; then
        bail "Docker is required"
    fi

    if [ -z "$DOCKER_VERSION" ] && [ -z "$CONTAINERD_VERSION" ]; then
            force_docker
    fi

    return 0
}

selinux_enabled() {
    if commandExists "selinuxenabled"; then
        selinuxenabled
        return
    elif commandExists "sestatus"; then
        ENABLED=$(sestatus | grep 'SELinux status' | awk '{ print $3 }')
        echo "$ENABLED" | grep --quiet --ignore-case enabled
        return
    fi

    return 1
}

selinux_enforced() {
    if commandExists "getenforce"; then
        ENFORCED=$(getenforce)
        echo $(getenforce) | grep --quiet --ignore-case enforcing
        return
    elif commandExists "sestatus"; then
        ENFORCED=$(sestatus | grep 'SELinux mode' | awk '{ print $3 }')
        echo "$ENFORCED" | grep --quiet --ignore-case enforcing
        return
    fi

    return 1
}

function kotsadm_prerelease() {
    if [ -n "$TESTGRID_ID" ]; then
        printf "\n${YELLOW}This is a prerelease version of kotsadm and should not be run in production. Continuing because this is testgrid.${NC} "
        return 0
    fi

    if [ "$KOTSADM_VERSION" = "alpha" ]; then
        printf "\n${YELLOW}This is a prerelease version of kotsadm and should not be run in production. Press Y to continue.${NC} "
        if ! confirmN; then
            bail "\nWill not install prerelease version of kotsadm."
        fi
    fi
}

function host_nameservers_reachable() {
    if [ -n "$NAMESERVER" ] || [ "$AIRGAP" = "1" ]; then
        return 0
    fi
    if ! discover_non_loopback_nameservers; then
        bail "\nAt least one nameserver must be accessible on a non-loopback address. Use the \"nameserver\" flag in the installer spec to override the loopback nameservers discovered on the host: https://kurl.sh/docs/add-ons/kurl"
    fi
}

function preflights_require_no_kubernetes_or_current_node() {
    if kubernetes_is_join_node ; then
        if kubernetes_is_current_cluster "${API_SERVICE_ADDRESS}" ; then
            return 0
        fi

        logWarn "Kubernetes is already installed on this Node but the api server endpoint is different."
        printf "${YELLOW}Are you sure you want to proceed? ${NC}" 1>&2
        if ! confirmN; then
            exit 1
        fi
        return 0
    fi

    if kubernetes_is_installed ; then
        bail "Kubernetes is already installed on this Node."
    fi

    return 0
}

function host_preflights() {
    local is_primary="$1"
    local is_join="$2"
    local is_upgrade="$3"

    local opts=
    if [ "${PREFLIGHT_IGNORE_WARNINGS}" = "1" ] || ! prompts_can_prompt ; then
        opts="${opts} --ignore-warnings"
    fi
    if [ "${is_primary}" != "1" ]; then
        opts="${opts} --is-primary=false"
    fi
    if [ "${is_join}" = "1" ]; then
        opts="${opts} --is-join"
    fi
    if [ "${is_upgrade}" = "1" ]; then
        opts="${opts} --is-upgrade"
    fi

    for spec in $(${K8S_DISTRO}_addon_for_each addon_preflight); do
        opts="${opts} --spec=${spec}"
    done

    if [ -n "$PRIMARY_HOST" ]; then
        opts="${opts} --primary-host=${PRIMARY_HOST}"
    fi
    if [ -n "$SECONDARY_HOST" ]; then
        opts="${opts} --secondary-host=${SECONDARY_HOST}"
    fi

    logStep "Running host preflights"
    if [ "${PREFLIGHT_IGNORE}" = "1" ]; then
        "${DIR}"/bin/kurl host preflight "${MERGED_YAML_SPEC}" ${opts} || true
        # TODO: report preflight fail
    else
        # interactive terminal
        if prompts_can_prompt; then
            set +e
            "${DIR}"/bin/kurl host preflight "${MERGED_YAML_SPEC}" ${opts} </dev/tty
            local kurl_exit_code=$?
            set -e 
            case $kurl_exit_code in
                3)
                    printf "${YELLOW}Host preflights have warnings${NC}\n"

                    # report_install_fail "preflight"
                    # bail "Use the \"preflight-ignore-warnings\" flag to proceed."
                    # printf "${YELLOW}Host preflights have warnings. Do you want to proceed anyway? ${NC} "
                    # if ! confirmY ; then
                    #     report_install_fail "preflight"
                    #     bail "Use the \"preflight-ignore-warnings\" flag to proceed."
                    # fi
                    return 0
                    ;;  
                1)
                    printf "${RED}Host preflights have failures${NC}\n"

                    # printf "${RED}Host preflights have failures. Do you want to proceed anyway? ${NC} "
                    # if ! confirmN ; then
                    #     report_install_fail "preflight"
                    #     bail "Use the \"preflight-ignore\" flag to proceed."
                    # fi
                    return 0
                    ;;
            esac                                       
        # non-interactive terminal
        else
            if ! "${DIR}"/bin/kurl host preflight "${MERGED_YAML_SPEC}" ${opts}; then
                # report_install_fail "preflight"
                # bail "Use the \"preflight-ignore\" flag to proceed."
                printf "${RED}Host preflights failed${NC}\n"
                return 0
            fi
        fi
    fi
    logStep "Host preflights success"
}
