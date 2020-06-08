
function preflights() {
    require64Bit
    bailIfUnsupportedOS
    mustSwapoff
    checkDockerK8sVersion
    checkFirewalld
    must_disable_selinux
    apply_iptables_config
    require_docker
    kotsadm_prerelease

    return 0
}

function requireRootUser() {
    return 0
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
        ubuntu16.04|ubuntu18.04|rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8|centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|amzn2)
            ;;
        *)
            bail "Kubernetes install is not supported on ${LSB_DIST} ${DIST_VERSION}"
            ;;
    esac
}
 
function mustSwapoff() {
    if swapEnabled || swapConfigured ; then
        printf "\n${YELLOW}This application is incompatible with memory swapping enabled. Disable swap to continue?${NC} "
        if confirmY ; then
            printf "=> Running swapoff --all\n"
            swapoff --all
            if swapConfigured ; then
              printf "=> Commenting swap entries in /etc/fstab \n"
              sed --in-place=.bak '/\bswap\b/ s/^/#/' /etc/fstab
              printf "=> A backup of /etc/fstab has been made at /etc/fstab.bak\n\n"
              printf "\n${YELLOW}Changes have been made to /etc/fstab. We recommend reviewing them after completing this installation to ensure mounts are correctly configured.${NC}\n\n"
              sleep 5 # for emphasis of the above ^
            fi
            logSuccess "Swap disabled.\n"
        else
            bail "\nDisable swap with swapoff --all and remove all swap entries from /etc/fstab before re-running this script"
        fi
    fi
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
    if confirmY ; then
        BYPASS_FIREWALLD_WARNING=1
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

swapEnabled() {
   swapon --summary | grep --quiet " " # todo this could be more specific, swapon -s returns nothing if its off
}

swapConfigured() {
	    cat /etc/fstab | grep --quiet --ignore-case --extended-regexp '^[^#]+swap'
}

function require_docker() {
	if commandExists docker ; then
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
    if [ "$KOTSADM_VERSION" = "alpha" ]; then
        printf "\n${YELLOW}This is a prerelease version of kotsadm and should not be run in production. Press Y to continue.${NC} "
        if ! confirmN; then
            bail "\nWill not install prerelease version of kotsadm."
        fi
    fi
}
