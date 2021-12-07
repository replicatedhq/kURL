GREEN='\033[0;32m'
BLUE='\033[0;94m'
LIGHT_BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

KUBEADM_CONF_DIR=/opt/replicated
KUBEADM_CONF_FILE="$KUBEADM_CONF_DIR/kubeadm.conf"

commandExists() {
    command -v "$@" > /dev/null 2>&1
}

function get_dist_url() {
    if [ -n "${KURL_VERSION}" ]; then
        echo "${DIST_URL}/${KURL_VERSION}"
    else
        echo "${DIST_URL}"
    fi
}

function package_download() {
    local package="$1"

    if [ -z "${DIST_URL}" ]; then
        logWarn "DIST_URL not set, will not download $1"
        return
    fi

    mkdir -p assets
    touch assets/Manifest

    local etag="$(cat assets/Manifest | grep "${package}" | awk 'NR == 1 {print $2}')"
    local checksum="$(cat assets/Manifest | grep "${package}" | awk 'NR == 1 {print $3}')"

    if [ -n "${etag}" ] && ! package_matches_checksum "${package}" "${checksum}" ; then
        etag=
    fi

    local newetag="$(curl -IfsSL "$(get_dist_url)/${package}" | grep -i 'etag:' | sed -r 's/.*"(.*)".*/\1/')"
    if [ -n "${etag}" ] && [ "${etag}" = "${newetag}" ]; then
        echo "Package ${package} already exists, not downloading"
        return
    fi

    sed -i "/^$(printf '%s' "${package}").*/d" assets/Manifest # remove from manifest

    local filepath="$(package_filepath "${package}")"

    echo "Downloading package ${package}"
    curl -fL -o "${filepath}" "$(get_dist_url)/${package}"

    checksum="$(md5sum "${filepath}" | awk '{print $1}')"
    echo "${package} ${newetag} ${checksum}" >> assets/Manifest
}

function package_filepath() {
    local package="$1"
    echo "assets/${package}"
}

function package_matches_checksum() {
    local package="$1"
    local checksum="$2"

    local filepath="$(package_filepath "${package}")"

    if [ -z "${checksum}" ]; then
        return 1
    elif [ ! -f "${filepath}" ] || [ ! -s "${filepath}" ]; then # if not exists or empty
        return 1
    elif ! md5sum "${filepath}" | grep -Fq "${checksum}" ; then
        echo "Package ${package} checksum does not match"
        return 1
    fi
    return 0
}

function package_cleanup() {
    if [ -z "${DIST_URL}" ] || [ "${AIRGAP}" = "1" ]; then
        return
    fi
    addon_cleanup
    rm -rf "${DIR}/packages"
}

insertOrReplaceJsonParam() {
    if ! [ -f "$1" ]; then
        # If settings file does not exist
        mkdir -p "$(dirname "$1")"
        echo "{\"$2\": \"$3\"}" > "$1"
    else
        # Settings file exists
        if grep -q -E "\"$2\" *: *\"[^\"]*\"" "$1"; then
            # If settings file contains named setting, replace it
            sed -i -e "s/\"$2\" *: *\"[^\"]*\"/\"$2\": \"$3\"/g" "$1"
        else
            # Insert into settings file (with proper commas)
            if [ $(wc -c <"$1") -ge 5 ]; then
                # File long enough to actually have an entry, insert "name": "value",\n after first {
                _commonJsonReplaceTmp="$(awk "NR==1,/^{/{sub(/^{/, \"{\\\"$2\\\": \\\"$3\\\", \")} 1" "$1")"
                echo "$_commonJsonReplaceTmp" > "$1"
            else
                # file not long enough to actually have contents, replace wholesale
                echo "{\"$2\": \"$3\"}" > "$1"
            fi
        fi
    fi
}

semverParse() {
    major="${1%%.*}"
    minor="${1#$major.}"
    minor="${minor%%.*}"
    patch="${1#$major.$minor.}"
    patch="${patch%%[-.]*}"
}

SEMVER_COMPARE_RESULT=
semverCompare() {
    semverParse "$1"
    _a_major="${major:-0}"
    _a_minor="${minor:-0}"
    _a_patch="${patch:-0}"
    semverParse "$2"
    _b_major="${major:-0}"
    _b_minor="${minor:-0}"
    _b_patch="${patch:-0}"
    if [ "$_a_major" -lt "$_b_major" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_major" -gt "$_b_major" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    if [ "$_a_minor" -lt "$_b_minor" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_minor" -gt "$_b_minor" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    if [ "$_a_patch" -lt "$_b_patch" ]; then
        SEMVER_COMPARE_RESULT=-1
        return
    fi
    if [ "$_a_patch" -gt "$_b_patch" ]; then
        SEMVER_COMPARE_RESULT=1
        return
    fi
    SEMVER_COMPARE_RESULT=0
}

log() {
    printf "%s\n" "$1" 1>&2
}

logSuccess() {
    printf "${GREEN}✔ $1${NC}\n" 1>&2
}

logStep() {
    printf "${BLUE}⚙  $1${NC}\n" 1>&2
}

logSubstep() {
    printf "\t${LIGHT_BLUE}- $1${NC}\n" 1>&2
}

logFail() {
    printf "${RED}$1${NC}\n" 1>&2
}

logWarn() {
    printf "${YELLOW}$1${NC}\n" 1>&2
}

bail() {
    logFail "$@"
    exit 1
}

function wait_for_nodes() {
    if ! spinner_until 120 get_nodes_succeeds ; then
        # this should exit script on non-zero exit code and print error message
        kubectl get nodes 1>/dev/null
    fi
}

function get_nodes_succeeds() {
    kubectl get nodes >/dev/null 2>&1
}

function wait_for_default_namespace() {
    if ! spinner_until 120 has_default_namespace ; then
        kubectl get ns
        bail "No default namespace detected"
    fi
}

function has_default_namespace() {
    kubectl get ns | grep -q '^default' 2>/dev/null
}

# Label nodes as provisioned by kurl installation
# (these labels should have been added by kurl installation.
#  See kubeadm-init and kubeadm-join yaml files.
#  This bit will ensure the labels are added for pre-existing cluster
#  during a kurl upgrade.)
labelNodes() {
    for NODE in $(kubectl get nodes --no-headers | awk '{print $1}');do
        kurl_label=$(kubectl describe nodes $NODE | grep "kurl.sh\/cluster=true") || true
        if [[ -z $kurl_label ]];then
            kubectl label node --overwrite $NODE kurl.sh/cluster=true;
        fi
    done
}

spinnerPodRunning() {
    namespace=$1
    podPrefix=$2

    local delay=0.75
    local spinstr='|/-\'
    while ! kubectl -n "$namespace" get pods 2>/dev/null | grep "^$podPrefix" | awk '{ print $3}' | grep '^Running$' > /dev/null ; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

COMPARE_DOCKER_VERSIONS_RESULT=
compareDockerVersions() {
    # reset
    COMPARE_DOCKER_VERSIONS_RESULT=
    compareDockerVersionsIgnorePatch "$1" "$2"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -ne "0" ]; then
        return
    fi
    parseDockerVersion "$1"
    _a_patch="$DOCKER_VERSION_PATCH"
    parseDockerVersion "$2"
    _b_patch="$DOCKER_VERSION_PATCH"
    if [ "$_a_patch" -lt "$_b_patch" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=-1
        return
    fi
    if [ "$_a_patch" -gt "$_b_patch" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=1
        return
    fi
    COMPARE_DOCKER_VERSIONS_RESULT=0
}

COMPARE_DOCKER_VERSIONS_RESULT=
compareDockerVersionsIgnorePatch() {
    # reset
    COMPARE_DOCKER_VERSIONS_RESULT=
    parseDockerVersion "$1"
    _a_major="$DOCKER_VERSION_MAJOR"
    _a_minor="$DOCKER_VERSION_MINOR"
    parseDockerVersion "$2"
    _b_major="$DOCKER_VERSION_MAJOR"
    _b_minor="$DOCKER_VERSION_MINOR"
    if [ "$_a_major" -lt "$_b_major" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=-1
        return
    fi
    if [ "$_a_major" -gt "$_b_major" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=1
        return
    fi
    if [ "$_a_minor" -lt "$_b_minor" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=-1
        return
    fi
    if [ "$_a_minor" -gt "$_b_minor" ]; then
        COMPARE_DOCKER_VERSIONS_RESULT=1
        return
    fi
    COMPARE_DOCKER_VERSIONS_RESULT=0
}

DOCKER_VERSION_MAJOR=
DOCKER_VERSION_MINOR=
DOCKER_VERSION_PATCH=
DOCKER_VERSION_RELEASE=
parseDockerVersion() {
    # reset
    DOCKER_VERSION_MAJOR=
    DOCKER_VERSION_MINOR=
    DOCKER_VERSION_PATCH=
    DOCKER_VERSION_RELEASE=
    if [ -z "$1" ]; then
        return
    fi

    OLD_IFS="$IFS" && IFS=. && set -- $1 && IFS="$OLD_IFS"
    DOCKER_VERSION_MAJOR=$1
    DOCKER_VERSION_MINOR=$2
    OLD_IFS="$IFS" && IFS=- && set -- $3 && IFS="$OLD_IFS"
    DOCKER_VERSION_PATCH=$1
    DOCKER_VERSION_RELEASE=$2
}

exportKubeconfig() {
    local kubeconfig
    kubeconfig="$(${K8S_DISTRO}_get_kubeconfig)"

    current_user_sudo_group
    if [ -n "$FOUND_SUDO_GROUP" ]; then
        chown root:$FOUND_SUDO_GROUP ${kubeconfig}
    fi
    chmod 440 ${kubeconfig}
    if ! grep -q "kubectl completion bash" /etc/profile; then
        echo "export KUBECONFIG=${kubeconfig}" >> /etc/profile
        echo "source <(kubectl completion bash)" >> /etc/profile
    fi
}

function kubernetes_resource_exists() {
    local namespace=$1
    local kind=$2
    local name=$3

    kubectl -n "$namespace" get "$kind" "$name" &>/dev/null
}

function install_cri() {
    # In the event someone changes the installer spec from docker to containerd, maintain backward capability with old installs
    if [ -n "$DOCKER_VERSION" ] ; then
        export REPORTING_CONTEXT_INFO="docker $DOCKER_VERSION"
        report_install_docker
        export REPORTING_CONTEXT_INFO=""
    elif [ -n "$CONTAINERD_VERSION" ]; then
        export REPORTING_CONTEXT_INFO="containerd $CONTAINERD_VERSION"
        report_install_containerd
        export REPORTING_CONTEXT_INFO=""
    fi
}

function report_install_docker() {
    report_addon_start "docker" "$DOCKER_VERSION"
    install_docker
    apply_docker_config
    report_addon_success "docker" "$DOCKER_VERSION"
}

function report_install_containerd() {
    containerd_get_host_packages_online "$CONTAINERD_VERSION"
    addon_install containerd "$CONTAINERD_VERSION"
}

function load_images() {
    if [ -n "$DOCKER_VERSION" ]; then
        find "$1" -type f | xargs -I {} bash -c "docker load < {}"
    else
        find "$1" -type f | xargs -I {} bash -c "cat {} | gunzip | ctr -a $(${K8S_DISTRO}_get_containerd_sock) -n=k8s.io images import -"
    fi
}

# try a command every 2 seconds until it succeeds, up to 30 tries max; useful for kubectl commands
# where the Kubernetes API could be restarting
function try_1m() {
    local fn="$1"
    local args=${@:2}

    n=0
    while ! $fn $args 2>/dev/null ; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "30" ]; then
            # for the final try print the error and let it exit
            echo ""
            try_output="$($fn $args 2>&1)" || true
            echo "$try_output"
            bail "spent 1m attempting to run \"$fn $args\" without success"
        fi
        sleep 2
    done
}

# try a command every 2 seconds until it succeeds, up to 150 tries max; useful for kubectl commands
# where the Kubernetes API could be restarting
function try_5m() {
    local fn="$1"
    local args=${@:2}

    n=0
    while ! $fn $args 2>/dev/null ; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "150" ]; then
            # for the final try print the error and let it exit
            echo ""
            try_output="$($fn $args 2>&1)" || true
            echo "$try_output"
            bail "spent 5m attempting to run \"$fn $args\" without success"
        fi
        sleep 2
    done
}

# try a command every 2 seconds until it succeeds, up to 30 tries max; useful for kubectl commands
# where the Kubernetes API could be restarting
# does not redirect stderr to /dev/null
function try_1m_stderr() {
    local fn="$1"
    local args=${@:2}

    n=0
    while ! $fn $args ; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "30" ]; then
            # for the final try print the error and let it exit
            echo ""
            try_output="$($fn $args 2>&1)" || true
            echo "$try_output"
            bail "spent 1m attempting to run \"$fn $args\" without success"
        fi
        sleep 2
    done
}

# Run a test every second with a spinner until it succeeds
function spinner_until() {
    local timeoutSeconds="$1"
    local cmd="$2"
    local args=${@:3}

    if [ -z "$timeoutSeconds" ]; then
        timeoutSeconds=-1
    fi

    local delay=1
    local elapsed=0
    local spinstr='|/-\'

    while ! $cmd $args; do
        elapsed=$(($elapsed + $delay))
        if [ "$timeoutSeconds" -ge 0 ] && [ "$elapsed" -gt "$timeoutSeconds" ]; then
            return 1
        fi
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

function get_common() {
    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        curl -sSOL "$(get_dist_url)/common.tar.gz"
        tar xf common.tar.gz
        rm common.tar.gz
    fi
}

function get_shared() {
    if [ -f shared/kurl-util.tar ]; then
        if [ -n "$DOCKER_VERSION" ]; then
            docker load < shared/kurl-util.tar
        else
            ctr -a "$(${K8S_DISTRO}_get_containerd_sock)" -n=k8s.io images import shared/kurl-util.tar
        fi
    fi
}

function all_sudo_groups() {
    # examples of lines we're looking for in any sudo config files to find group with root privileges
    # %wheel ALL = (ALL) ALL
    # %google-sudoers ALL=(ALL:ALL) NOPASSWD:ALL
    # %admin ALL=(ALL) ALL
    cat /etc/sudoers | grep -Eo '^%\S+\s+ALL\s?=.*ALL\b' | awk '{print $1 }' | sed 's/%//'
    find /etc/sudoers.d/ -type f | xargs cat | grep -Eo '^%\S+\s+ALL\s?=.*ALL\b' | awk '{print $1 }' | sed 's/%//'
}

# if the sudo group cannot be detected default to root
FOUND_SUDO_GROUP=
function current_user_sudo_group() {
    if [ -z "$SUDO_UID" ]; then
        return 0
    fi
    # return the first sudo group the current user belongs to
    while read -r groupName; do
        if id "$SUDO_UID" -Gn | grep -q "\b${groupName}\b"; then
            FOUND_SUDO_GROUP="$groupName"
            return 0
        fi
    done < <(all_sudo_groups)
}

function kubeconfig_setup_outro() {
    current_user_sudo_group
    if [ -n "$FOUND_SUDO_GROUP" ]; then
        printf "To access the cluster with kubectl, reload your shell:\n"
        printf "\n"
        printf "${GREEN}    bash -l${NC}\n"
        return
    fi
    local owner="$SUDO_UID"
    if [ -z "$owner" ]; then
        # not currently running via sudo
        owner="$USER"
    else
        # running via sudo - automatically create ~/.kube/config if it does not exist
        ownerdir=`eval echo "~$(id -un $owner)"`

        if [ ! -f "$ownerdir/.kube/config" ]; then
            mkdir -p $ownerdir/.kube
            cp "$(${K8S_DISTRO}_get_kubeconfig)" $ownerdir/.kube/config
            chown -R $owner $ownerdir/.kube

            printf "To access the cluster with kubectl, ensure the KUBECONFIG environment variable is unset:\n"
            printf "\n"
            printf "${GREEN}    echo unset KUBECONFIG >> ~/.bash_profile${NC}\n"
            printf "${GREEN}    bash -l${NC}\n"
            return
        fi
    fi

    printf "To access the cluster with kubectl, copy kubeconfig to your home directory:\n"
    printf "\n"
    printf "${GREEN}    cp "$(${K8S_DISTRO}_get_kubeconfig)" ~/.kube/config${NC}\n"
    printf "${GREEN}    chown -R ${owner} ~/.kube${NC}\n"
    printf "${GREEN}    echo unset KUBECONFIG >> ~/.bash_profile${NC}\n"
    printf "${GREEN}    bash -l${NC}\n"
    printf "\n"
    printf "You will likely need to use sudo to copy and chown "$(${K8S_DISTRO}_get_kubeconfig)".\n"
}

splitHostPort() {
    oIFS="$IFS"; IFS=":" read -r HOST PORT <<< "$1"; IFS="$oIFS"
}

isValidIpv4() {
    if echo "$1" | grep -qs '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
        return 0
    else
        return 1
    fi
}

isValidIpv6() {
    if echo "$1" | grep -qs "^\([0-9a-fA-F]\{0,4\}:\)\{1,7\}[0-9a-fA-F]\{0,4\}$"; then
        return 0
    else
        return 1
    fi
}

function cert_has_san() {
    local address=$1
    local san=$2

    echo "Q" | openssl s_client -connect "$address" 2>/dev/null | openssl x509 -noout -text 2>/dev/null | grep --after-context=1 'X509v3 Subject Alternative Name' | grep -q "$2"
}

# By default journald persists logs if the directory /var/log/journal exists so create it if it's
# not found. Sysadmins may still disable persistent logging with /etc/systemd/journald.conf.
function journald_persistent() {
    if [ -d /var/log/journal ]; then
        return 0
    fi
    mkdir -p /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal
    systemctl restart systemd-journald
    journalctl --flush
}

function rm_file() {
    if [ -f "$1" ]; then
        rm $1
    fi
}

# Checks if the provided param is in the current path, and if it is not adds it
# this is useful for systems where /usr/local/bin is not in the path for root
function path_add() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="${PATH:+"$PATH:"}$1"
    fi
}

function install_host_dependencies() {
    install_host_dependencies_openssl
}

function install_host_dependencies_openssl() {
    if commandExists "openssl"; then
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        local package="host-openssl.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")"
    fi
    install_host_archives "${DIR}/packages/host/openssl" openssl
}

function maybe_read_kurl_config_from_cluster() {
    if [ -n "${KURL_INSTALL_DIRECTORY_FLAG}" ]; then
        return
    fi

    local kurl_install_directory_flag
    # we don't yet have KUBECONFIG when this is called from the top of install.sh
    kurl_install_directory_flag="$(KUBECONFIG="$(kubeadm_get_kubeconfig)" kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.kurl_install_directory }' 2>/dev/null || echo "")"
    if [ -z "${kurl_install_directory_flag}" ]; then
        kurl_install_directory_flag="$(KUBECONFIG="$(rke2_get_kubeconfig)" kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.kurl_install_directory }' 2>/dev/null || echo "")"
    fi
    if [ -n "${kurl_install_directory_flag}" ]; then
        KURL_INSTALL_DIRECTORY_FLAG="${kurl_install_directory_flag}"
        KURL_INSTALL_DIRECTORY="$(realpath ${kurl_install_directory_flag})/kurl"
    fi

    # this function currently only sets KURL_INSTALL_DIRECTORY
    # there are many other settings in kurl-config
}

KURL_INSTALL_DIRECTORY=/var/lib/kurl
function pushd_install_directory() {
    local tmpfile
    tmpfile="${KURL_INSTALL_DIRECTORY}/tmpfile"
    if ! mkdir -p "${KURL_INSTALL_DIRECTORY}" || ! touch "${tmpfile}" ; then
        bail "Directory ${KURL_INSTALL_DIRECTORY} is not writeable by this script.
Please either change the directory permissions or override the
installation directory with the flag \"kurl-install-directory\"."
    fi
    rm "${tmpfile}"
    pushd "${KURL_INSTALL_DIRECTORY}" 1>/dev/null
}

function popd_install_directory() {
    popd 1>/dev/null
}

function move_airgap_assets() {
    local cwd
    cwd="$(pwd)"

    if [ "$(readlink -f $KURL_INSTALL_DIRECTORY)" = "${cwd}/kurl" ]; then
        return
    fi

    pushd_install_directory # make sure we have access
    popd_install_directory

    # The airgap bundle will extract everything into ./kurl directory.
    # Move all assets except the scripts into the $KURL_INSTALL_DIRECTORY to emulate the online install experience.
    if [ "$(ls -A "${cwd}"/kurl)" ]; then
        for file in "${cwd}"/kurl/*; do
            rm -rf "${KURL_INSTALL_DIRECTORY}/$(basename ${file})"
            mv "${file}" "${KURL_INSTALL_DIRECTORY}/"
        done
    fi
}

function get_docker_registry_ip_flag() {
    local docker_registry_ip="$1"
    if [ -z "${docker_registry_ip}" ]; then
        return
    fi
    echo " docker-registry-ip=${docker_registry_ip}"
}

function get_force_reapply_addons_flag() {
    if [ "${FORCE_REAPPLY_ADDONS}" != "1" ]; then
        return
    fi
    echo " force-reapply-addons"
}

function get_additional_no_proxy_addresses_flag() {
    local has_proxy="$1"
    local no_proxy_addresses="$2"
    if [ -z "${has_proxy}" ]; then
        return
    fi
    echo " additional-no-proxy-addresses=${no_proxy_addresses}"
}

function get_kurl_install_directory_flag() {
    local kurl_install_directory="$1"
    if [ -z "${kurl_install_directory}" ] || [ "${kurl_install_directory}" = "/var/lib/kurl" ]; then
        return
    fi
    echo " kurl-install-directory=$(echo "${kurl_install_directory}")"
}

function get_remotes_flags() {
    while read -r primary; do
        printf " primary-host=$primary"
    done < <(kubectl get nodes --no-headers --selector="node-role.kubernetes.io/master" -owide | awk '{ print $6 }')

    while read -r secondary; do
        printf " secondary-host=$secondary"
    done < <(kubectl get node --no-headers --selector='!node-role.kubernetes.io/master' -owide | awk '{ print $6 }')
}

function systemd_restart_succeeded() {
    local oldPid=$1
    local serviceName=$2

    if ! systemctl is-active --quiet $serviceName; then
        return 1
    fi

    local newPid="$(systemctl show --property MainPID $serviceName | cut -d = -f2)"
    if [ "$newPid" = "$oldPid" ]; then
        return 1
    fi

    if ps -p $oldPid >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

function restart_systemd_and_wait() {
    local serviceName=$1

    local pid="$(systemctl show --property MainPID $serviceName | cut -d = -f2)"

    echo "Restarting $serviceName..."
    systemctl restart $serviceName

    if ! spinner_until 120 systemd_restart_succeeded $pid $serviceName; then
        journalctl -xe
        bail "Could not successfully restart systemd service $serviceName"
    fi

    echo "Service $serviceName restarted."
}

# returns true when a job has completed
function job_is_completed() {
  local namespace="$1"
  local jobName="$2"
  kubectl get jobs -n "$namespace" "$jobName" | grep -q '1/1'
}

function maybe() {
    local cmd="$1"
    local args=${@:2}

    $cmd $args 2>/dev/null || true
}

MACHINE_ID=
function get_machine_id() {
    MACHINE_ID="$(${DIR}/bin/kurl host protectedid || true)"
}

function kebab_to_camel() {
    echo "$1" | sed -E 's/-(.)/\U\1/g'
}

function build_installer_prefix() {
    local installer_id="$1"
    local kurl_version="$2"
    local kurl_url="$3"
    local proxy_address="$4"

    if [ -z "${kurl_url}" ]; then
        echo "cat "
        return
    fi

    local curl_flags=
    if [ -n "${proxy_address}" ]; then
        curl_flags=" -x ${proxy_address}"
    fi

    if [ -n "${kurl_version}" ]; then
        echo "curl -fsSL${curl_flags} ${kurl_url}/version/${kurl_version}/${installer_id}/"
    else
        echo "curl -fsSL${curl_flags} ${kurl_url}/${installer_id}/"
    fi
}

function get_local_node_name() {
    hostname | tr '[:upper:]' '[:lower:]'
}
