
function preflights() {
    require64Bit
    bailIfUnsupportedOS
    mustSwapoff
    prompt_if_docker_unsupported_os
    check_docker_k8s_version
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
        ubuntu16.04)
            logWarn "Install is not supported on Ubuntu 16.04. Installation of Kubernetes will be best effort."
            ;;
        ubuntu18.04|ubuntu20.04|ubuntu22.04)
            ;;
        rhel7.4|rhel7.5|rhel7.6|rhel7.7|rhel7.8|rhel7.9|rhel8.0|rhel8.1|rhel8.2|rhel8.3|rhel8.4|rhel8.5|rhel8.6|rhel8.7)
            ;;
        centos7.4|centos7.5|centos7.6|centos7.7|centos7.8|centos7.9|centos8|centos8.0|centos8.1|centos8.2|centos8.3|centos8.4)
            ;;
        amzn2)
            ;;
        ol7.4|ol7.5|ol7.6|ol7.7|ol7.8|ol7.9|ol8.0|ol8.1|ol8.2|ol8.3|ol8.4|ol8.5|ol8.6|ol8.7)
            ;;
        *)
            bail "Kubernetes install is not supported on ${LSB_DIST} ${DIST_VERSION}. The list of supported operating systems can be viewed at https://kurl.sh/docs/install-with-kurl/system-requirements."
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


function check_docker_k8s_version() {
    local version=
    version="$(get_docker_version)"

    if [ -z "$version" ]; then
        return
    fi

    case "$KUBERNETES_TARGET_VERSION_MINOR" in 
        14|15)
            compareDockerVersions "$version" 1.13.1
            if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
                bail "Minimum Docker version for Kubernetes $KUBERNETES_VERSION is 1.13.1."
            fi
            ;;
    esac
}

function prompt_if_docker_unsupported_os() {
    if is_docker_version_supported ; then
        return
    fi

    logWarn "Docker ${DOCKER_VERSION} is not supported on ${LSB_DIST} ${DIST_VERSION}."
    logWarn "The containerd addon is recommended. https://kurl.sh/docs/add-ons/containerd"

    if commandExists "docker" ; then
        return
    fi

    printf "${YELLOW}Continue? ${NC}" 1>&2
    if ! confirmY ; then
        exit 1
    fi
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
    DOCKER_VERSION="20.10.17"
    printf "${YELLOW}NO CRI version was listed in yaml or found on host OS, defaulting to online docker install${NC}\n"
    printf "${YELLOW}THIS FEATURE IS NOT SUPPORTED AND WILL BE DEPRECATED IN FUTURE KURL VERSIONS${NC}\n"
    printf "${YELLOW}The installer did not specify a version of Docker or Containerd to include, but having one is required by all kURL installation scripts. The latest supported version ($DOCKER_VERSION) of Docker will be installed.${NC}\n"
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
         if [ -n "$NO_CE_ON_EE" ] && [ -z "$CONTAINERD_VERSION" ]; then
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
        printf "\n${YELLOW}This is a prerelease version of kotsadm and should not be run in production. Continuing because this is testgrid.${NC}\n"
        return 0
    fi

    if [ "$KOTSADM_VERSION" = "alpha" ] || [ "$KOTSADM_VERSION" = "nightly" ]; then
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

function preflights_system_packages() {
  local addonName=$1
  local addonVersion=$2

  local manifestPath="${DIR}/addons/${addonName}/${addonVersion}/Manifest"
  local preflightPath="${DIR}/addons/${addonName}/${addonVersion}/system-packages-preflight.yaml"

  if [ ! -f "$manifestPath" ]; then
      return
  fi

  local pkgs_all=()
  local pkgs_ubuntu=()
  local pkgs_centos=()
  local pkgs_centos8=()
  local pkgs_ol=()

  while read -r line; do
      if [ -z "$line" ]; then
          continue
      fi
      # support for comments in manifest files
      if [ "$(echo "$line" | cut -c1-1)" = "#" ]; then
          continue
      fi
      kind=$(echo "$line" | awk '{ print $1 }')

      case "$kind" in
          apt)
              package=$(echo "${line}" | awk '{ print $2 }')
              pkgs_ubuntu+=("${package}")
              pkgs_all+=("${package}")
              ;;

          yum)
              package=$(echo "${line}" | awk '{ print $2 }')
              pkgs_centos+=("${package}")
              pkgs_all+=("${package}")
              ;;

          yum8)
              package=$(echo "${line}" | awk '{ print $2 }')
              pkgs_centos8+=("${package}")
              pkgs_all+=("${package}")
              ;;

          yumol)
              package=$(echo "${line}" | awk '{ print $2 }')
              pkgs_ol+=("${package}")
              pkgs_all+=("${package}")
              ;;
      esac
  done < "${manifestPath}"

  if [ "${#pkgs_all[@]}" -eq "0" ]; then
      return
  fi

  local system_packages_collector="
systemPackages:
  collectorName: $addonName
"

  local system_packages_analyzer="
systemPackages:
  collectorName: $addonName
  outcomes:
  - fail:
      when: '{{ not .IsInstalled }}'
      message: Package {{ .Name }} is not installed.
  - pass:
      message: Package {{ .Name }} is installed.
"

  for pkg in "${pkgs_ubuntu[@]}"
  do
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_ubuntu[] -v "$pkg")
  done

  for pkg in "${pkgs_centos[@]}"
  do
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_centos[] -v "$pkg")
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_rhel[] -v "$pkg")
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_ol[] -v "$pkg")
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_amzn[] -v "$pkg")
  done

  for pkg in "${pkgs_centos8[@]}"
  do
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_centos8[] -v "$pkg")
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_rhel8[] -v "$pkg")
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_ol8[] -v "$pkg")
  done

  for pkg in "${pkgs_ol[@]}"
  do
      system_packages_collector=$("${DIR}"/bin/yamlutil -a -yc "$system_packages_collector" -yp systemPackages_ol[] -v "$pkg")
  done

  # host preflight file not found, create one
  rm -rf "$preflightPath"
  mkdir -p "$(dirname "$preflightPath")"
  cat <<EOF >> "$preflightPath"
apiVersion: troubleshoot.sh/v1beta2
kind: HostPreflight
metadata:
  name: "$addonName"
spec:
  collectors: []
  analyzers: []
EOF

  "${DIR}"/bin/yamlutil -a -fp "$preflightPath" -yp spec_collectors[] -v "$system_packages_collector"
  "${DIR}"/bin/yamlutil -a -fp "$preflightPath" -yp spec_analyzers[] -v "$system_packages_analyzer"

  echo "$preflightPath"
}

HOST_PREFLIGHTS_RESULTS_OUTPUT_DIR="host-preflights"
function host_preflights() {
    local is_primary="$1"
    local is_join="$2"
    local is_upgrade="$3"

    local opts=

    local out_file=
    out_file="${DIR}/${HOST_PREFLIGHTS_RESULTS_OUTPUT_DIR}/results-$(date +%s).txt"

    mkdir -p "${DIR}/${HOST_PREFLIGHTS_RESULTS_OUTPUT_DIR}"

    if [ ! "${HOST_PREFLIGHT_ENFORCE_WARNINGS}" = "1" ] ; then
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

    # Remove previous file if it exists
    if [ -f "${VENDOR_PREFLIGHT_SPEC}" ]; then
      rm "$VENDOR_PREFLIGHT_SPEC"
    fi
    
    $DIR/bin/vendorflights -i "${MERGED_YAML_SPEC}" -o "${VENDOR_PREFLIGHT_SPEC}"
    if [ -f "${VENDOR_PREFLIGHT_SPEC}" ]; then
      opts="${opts} --spec=${VENDOR_PREFLIGHT_SPEC}"
    fi

    if [ "$EXCLUDE_BUILTIN_HOST_PREFLIGHTS" == "1" ]; then
        opts="${opts} --exclude-builtin"
    else
        # Adding kurl addon preflight checks
        for spec in $("${K8S_DISTRO}_addon_for_each" addon_preflight); do
            opts="${opts} --spec=${spec}"
        done
        # Add containerd preflight checks separately since it's a special addon and is not part of the addons array
        for spec in $(addon_preflight containerd "$CONTAINERD_VERSION"); do
            opts="${opts} --spec=${spec}"
        done
    fi

    if [ -n "$PRIMARY_HOST" ]; then
        opts="${opts} --primary-host=${PRIMARY_HOST}"
    fi
    if [ -n "$SECONDARY_HOST" ]; then
        opts="${opts} --secondary-host=${SECONDARY_HOST}"
    fi

    logStep "Running host preflights"
    if [ "${HOST_PREFLIGHT_IGNORE}" = "1" ]; then
        "${DIR}"/bin/kurl host preflight "${MERGED_YAML_SPEC}" ${opts} | tee "${out_file}"
        host_preflights_mkresults "${out_file}" "${opts}"

        # TODO: report preflight fail
    else
        set +e
        "${DIR}"/bin/kurl host preflight "${MERGED_YAML_SPEC}" ${opts} | tee "${out_file}"
        local kurl_exit_code="${PIPESTATUS[0]}"
        set -e

        host_preflights_mkresults "${out_file}" "${opts}"

        case $kurl_exit_code in
            3)
                bail "Host preflights have warnings that block the installation."
                ;;  
            2)
                logWarn "Host preflights have warnings"
                return 0
                ;;
            1)
                bail "Host preflights have failures that block the installation."
                ;;
        esac                                       
    fi
    logStep "Host preflights success"
}

# host_preflights_mkresults will append cli data to preflight results file
function host_preflights_mkresults() {
    local out_file="$1"
    local opts="$2"
    local kurl_version=
    kurl_version="$(./bin/kurl version | grep version= | awk 'BEGIN { FS="=" }; { print $2 }')"
    local tmp_file=
    tmp_file="$(mktemp)"
    echo -e "[version]\n${kurl_version}\n\n[options]\n${opts}\n\n[results]" | cat - "${out_file}" > "${tmp_file}" && mv "${tmp_file}" "${out_file}"
    chmod -R +r "${DIR}/${HOST_PREFLIGHTS_RESULTS_OUTPUT_DIR}/" # make sure the file is readable by kots support bundle
    rm -f "${tmp_file}"
}
