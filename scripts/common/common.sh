GREEN='\033[0;32m'
BLUE='\033[0;94m'
LIGHT_BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

KUBEADM_CONF_DIR=/opt/replicated
KUBEADM_CONF_FILE="$KUBEADM_CONF_DIR/kubeadm.conf"

function commandExists() {
    command -v "$@" > /dev/null 2>&1
}

function get_dist_url() {
    local url="$DIST_URL"
    if [ -n "${KURL_VERSION}" ]; then
        url="${DIST_URL}/${KURL_VERSION}"
    fi
    echo "$url"
}

# default s3 endpoint does not have AAAA records so IPv6 installs have to choose
# an arbitrary regional dualstack endpoint. If S3 transfer acceleration is ever
# enabled on the kurl-sh bucket the s3.accelerate.amazonaws.com endpoint can be
# used for both IPv4 and IPv6.
# this is not required for get_dist_url as *.kurl.sh endpoints have IPv6 addresses.
function get_dist_url_fallback() {
    local url="$FALLBACK_URL"
    if [ -n "${KURL_VERSION}" ]; then
        url="${FALLBACK_URL}/${KURL_VERSION}"
    fi

    if [ "$IPV6_ONLY" = "1" ]; then
        echo "$url" | sed 's/s3\.amazonaws\.com/s3.dualstack.us-east-1.amazonaws.com/'
    else
        echo "$url"
    fi
}

function package_download() {
    local package="$1"
    local url_override="$2"

    if [ -z "$package" ]; then
        bail "package_download called with no package name"
    fi

    if [ -z "$url_override" ] && [ -z "${DIST_URL}" ]; then
        logWarn "DIST_URL not set, will not download $1"
        return
    fi

    mkdir -p assets
    touch assets/Manifest

    local etag=
    local checksum=
    etag="$(grep -F "${package}" assets/Manifest | awk 'NR == 1 {print $2}')"
    checksum="$(grep -F "${package}" assets/Manifest | awk 'NR == 1 {print $3}')"

    if [ -n "${etag}" ] && ! package_matches_checksum "${package}" "${checksum}" ; then
        etag=
    fi

    local package_url=
    if [ -z "$url_override" ]; then
        package_url="$(get_dist_url)/${package}"
    else
        package_url="${url_override}"
    fi

    local newetag=
    newetag="$(curl -IfsSL "$package_url" | grep -i 'etag:' | sed -r 's/.*"(.*)".*/\1/')"
    if [ -n "${etag}" ] && [ "${etag}" = "${newetag}" ]; then
        echo "Package ${package} already exists, not downloading"
        return
    fi

    local filepath=
    filepath="$(package_filepath "${package}")"

    sed -i "/^$(printf '%s' "${package}").*/d" assets/Manifest # remove from manifest
    rm -f "${filepath}" # remove the file

    echo "Downloading package ${package}"
    if [ -z "$url_override" ]; then
        if [ -z "$FALLBACK_URL" ]; then
            package_download_url_with_retry "$package_url" "${filepath}"
        else
            package_download_url_with_retry "$package_url" "${filepath}" || package_download_url_with_retry "$(get_dist_url_fallback)/${package}" "${filepath}"
        fi
    else
        package_download_url_with_retry "${url_override}" "${filepath}"
    fi

    checksum="$(md5sum "${filepath}" | awk '{print $1}')"
    echo "${package} ${newetag} ${checksum}" >> assets/Manifest
}

function package_download_url_with_retry() {
    local url="$1"
    local filepath="$2"
    local max_retries="${3:-10}"

    local errcode=
    local i=0
    while [ $i -ne "$max_retries" ]; do
        errcode=0
        curl -fL -o "${filepath}" "${url}" || errcode="$?"
        # 18 transfer closed with outstanding read data remaining
        # 56 recv failure (connection reset by peer)
        if [ "$errcode" -eq "18" ] || [ "$errcode" -eq "56" ]; then
            i=$(($i+1))
            continue
        fi
        return "$errcode"
    done
    return "$errcode"
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

function insertOrReplaceJsonParam() {
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

function semverParse() {
    major="${1%%.*}"
    minor="${1#$major.}"
    minor="${minor%%.*}"
    patch="${1#$major.$minor.}"
    patch="${patch%%[-.]*}"
}

SEMVER_COMPARE_RESULT=
function semverCompare() {
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

function log() {
    printf "%s\n" "$1" 1>&2
}

function logSuccess() {
    printf "${GREEN}✔ $1${NC}\n" 1>&2
}

function logStep() {
    printf "${BLUE}⚙  $1${NC}\n" 1>&2
}

function logSubstep() {
    printf "\t${LIGHT_BLUE}- $1${NC}\n" 1>&2
}

function logFail() {
    printf "${RED}$1${NC}\n" 1>&2
}

function logWarn() {
    printf "${YELLOW}$1${NC}\n" 1>&2
}

function bail() {
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
function labelNodes() {
    for NODE in $(kubectl get nodes --no-headers | awk '{print $1}');do
        kurl_label=$(kubectl describe nodes $NODE | grep "kurl.sh\/cluster=true") || true
        if [[ -z $kurl_label ]];then
            kubectl label node --overwrite $NODE kurl.sh/cluster=true;
        fi
    done
}

# warning - this only waits for the pod to be running, not for it to be 1/1 or otherwise accepting connections
function spinnerPodRunning() {
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
function compareDockerVersions() {
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
function compareDockerVersionsIgnorePatch() {
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
function parseDockerVersion() {
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

function exportKubeconfig() {
    local kubeconfig
    kubeconfig="$(${K8S_DISTRO}_get_kubeconfig)"

    # To meet KUBERNETES_CIS_COMPLIANCE, the ${kubeconfig} needs to be owned by root:root
    # and permissions set to 600 so users other than root cannot have access to kubectl
    if [ "$KUBERNETES_CIS_COMPLIANCE" == "1" ]; then
        chown root:root ${kubeconfig}
        chmod 400 ${kubeconfig}
    else
        current_user_sudo_group
        if [ -n "$FOUND_SUDO_GROUP" ]; then
            chown root:$FOUND_SUDO_GROUP ${kubeconfig}
        fi
        chmod 440 ${kubeconfig}
    fi
    
    if ! grep -q "kubectl completion bash" /etc/profile; then
        if [ "$KUBERNETES_CIS_COMPLIANCE" != "1" ]; then
            echo "export KUBECONFIG=${kubeconfig}" >> /etc/profile
        fi
        echo "if  type _init_completion >/dev/null 2>&1; then source <(kubectl completion bash); fi" >> /etc/profile
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
    # if we haven't installed kubernetes yet we don't need to wory about containerd upgrades.
    if [ -z "$CURRENT_KUBERNETES_VERSION" ] ; then
        addon_install "containerd" "$CONTAINERD_VERSION"
        return 0
    fi

    # if the node we are running this script is leveraging docker we also don't need to worry
    # about the version of containerd we are installing, it won't be an upgrade anyways.
    if node_is_using_docker ; then
        addon_install "containerd" "$CONTAINERD_VERSION"
        return 0
    fi

    # if we can't find containerd in the local filesystem then we can also install regardless
    # of version.
    if [ ! -f "/usr/bin/containerd" ]; then
        addon_install "containerd" "$CONTAINERD_VERSION"
        return 0
    fi

    # from now on we are migrating from one containerd version to another, restrictions apply.
    local current_containerd_version
    current_containerd_version=$(/usr/bin/containerd --version | cut -d " " -f3 | tr -d 'v')
    containerd_evaluate_upgrade "$current_containerd_version" "$CONTAINERD_VERSION"
    for version in "${CONTAINERD_INSTALL_VERSIONS[@]}"; do
        logStep "Moving containerd to version v$version."
        if [ "$version" != "$CONTAINERD_VERSION" ] && [ "$AIRGAP" != "1" ] ; then
            log "Downloading containerd v$version."
            addon_fetch "containerd" "$version"
        fi
        addon_install "containerd" "$version"
    done
}

function load_images() {
    if [ -n "$DOCKER_VERSION" ]; then
        find "$1" -type f | xargs -I {} bash -c "docker load < {}"
    else
        find "$1" -type f | xargs -I {} bash -c "cat {} | gunzip | ctr -a $(${K8S_DISTRO}_get_containerd_sock) -n=k8s.io images import -"
    fi

    retag_gcr_images
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
        elapsed=$((elapsed + delay))
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

function sleep_spinner() {
    local sleepSeconds="${1:-0}"

    local delay=1
    local elapsed=0
    local spinstr='|/-\'

    while true ; do
        elapsed=$((elapsed + delay))
        if [ "$elapsed" -gt "$sleepSeconds" ]; then
            return 0
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
        if [ -z "$FALLBACK_URL" ]; then
            curl -sSOL "$(get_dist_url)/common.tar.gz"
        else
            curl -sSOL "$(get_dist_url)/common.tar.gz" || curl -sSOL "$(get_dist_url_fallback)/common.tar.gz"
        fi
        tar xf common.tar.gz --no-same-owner
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
    local owner="$SUDO_UID"
    if [ -z "$owner" ]; then
        # not currently running via sudo
        owner="$USER"
    else
        # running via sudo - automatically create ~/.kube/config if it does not exist
        ownerdir=$(eval echo "~$(id -un "$owner")")

        if [ ! -f "$ownerdir/.kube/config" ]; then
            mkdir -p $ownerdir/.kube
            cp "$(${K8S_DISTRO}_get_kubeconfig)" $ownerdir/.kube/config
            chown -R $owner $ownerdir/.kube

            printf "To access the cluster with kubectl:\n"
            printf "\n"
            printf "${GREEN}    bash -l${NC}\n"
            printf "Kurl uses "$(${K8S_DISTRO}_get_kubeconfig)", you might want to unset KUBECONFIG to use .kube/config:\n"
            printf "\n"
            printf "${GREEN}    echo unset KUBECONFIG >> ~/.bash_profile${NC}\n"
            return
        fi
    fi

    printf "To access the cluster with kubectl:\n"
    printf "\n"
    printf "${GREEN}    bash -l${NC}\n"
    printf "\n"
    printf "Kurl uses "$(${K8S_DISTRO}_get_kubeconfig)", you might want to copy kubeconfig to your home directory:\n"
    printf "\n"
    printf "${GREEN}    cp "$(${K8S_DISTRO}_get_kubeconfig)" ~/.kube/config${NC}\n"
    printf "${GREEN}    chown -R ${owner} ~/.kube${NC}\n"
    printf "${GREEN}    echo unset KUBECONFIG >> ~/.bash_profile${NC}\n"
    printf "${GREEN}    bash -l${NC}\n"
    printf "\n"
    printf "You will likely need to use sudo to copy and chown "$(${K8S_DISTRO}_get_kubeconfig)".\n"
}

function splitHostPort() {
    oIFS="$IFS"; IFS=":" read -r HOST PORT <<< "$1"; IFS="$oIFS"
}

function isValidIpv4() {
    if echo "$1" | grep -qs '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
        return 0
    else
        return 1
    fi
}

function isValidIpv6() {
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
    install_host_dependencies_fio || true # fio is not a hard requirement, just a nice-to-have
}

function install_host_dependencies_openssl() {
    if commandExists "openssl"; then
        return
    fi

    if is_rhel_9_variant ; then
        yum_ensure_host_package openssl
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        local package="host-openssl.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")" --no-same-owner
    fi
    install_host_archives "${DIR}/packages/host/openssl" openssl
}

function install_host_dependencies_fio() {
    if commandExists "fio"; then
        return
    fi

    if is_rhel_9_variant ; then
        if !  yum_ensure_host_package fio ; then
            logWarn "Failed to install fio, continuing anyways"
        fi
        return
    fi

    # if this is Ubuntu 18.04, do not install fio - there are python issues
    if [ "$LSB_DIST$DIST_VERSION" = "ubuntu18.04" ]; then
        logWarn "Skipping fio install on Ubuntu 18.04"
        return
    fi

    # we can't install fio on amazon linux because it brings, as a dependency,
    # a package called `centos-release` that ends up overwriting the amazon
    # linux release file, making it look like a centos machine.
    if [ "$LSB_DIST" = "amzn" ]; then
        logWarn "Skipping fio installation on Amazon Linux. If you prefer, you can cancel this"
        logWarn "installation now and manually install fio using 'yum install fio'. Ignoring this"
        logWarn "message may cause some of the preflight checks to generate warnings later on."
        logWarn "Do you want to continue with the installation without fio?"
        if ! confirmY ; then
            bail "Installation cancelled by user"
        fi
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        local package="host-fio.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")" --no-same-owner
    fi
    if ! install_host_archives "${DIR}/packages/host/fio" fio; then
        logWarn "Failed to install fio, continuing anyways"
    fi
}

function maybe_read_kurl_config_from_cluster() {
    # if KURL_INSTALL_DIRECTORY_FLAG is set, use the value from the flag
    if [ -z "$KURL_INSTALL_DIRECTORY_FLAG" ]; then
        local kurl_install_directory_flag
        # we don't yet have KUBECONFIG when this is called from the top of install.sh
        kurl_install_directory_flag="$(KUBECONFIG="$(kubeadm_get_kubeconfig)" kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.kurl_install_directory }' 2>/dev/null || echo "")"
        if [ -n "$kurl_install_directory_flag" ]; then
            KURL_INSTALL_DIRECTORY_FLAG="$kurl_install_directory_flag"
            KURL_INSTALL_DIRECTORY="$(realpath "$kurl_install_directory_flag")/kurl"
        fi
    fi

    # this function currently only sets KURL_INSTALL_DIRECTORY
    # there are many other settings in kurl-config
}

KURL_INSTALL_DIRECTORY=/var/lib/kurl
function pushd_install_directory() {
    local dir=
    dir="$(dirname "$KURL_INSTALL_DIRECTORY")"
    if [ ! -e "$dir" ] ; then
        bail "kURL installation directory $dir does not exist."
    fi
    if [ ! -d "$dir" ] ; then
        bail "kURL installation directory $dir is not a directory."
    fi

    KURL_INSTALL_DIRECTORY="$(realpath "$KURL_INSTALL_DIRECTORY")"

    local tmpfile=
    tmpfile="$KURL_INSTALL_DIRECTORY/tmpfile"
    if ! mkdir -p "$KURL_INSTALL_DIRECTORY" || ! touch "$tmpfile" ; then
        bail "Directory $KURL_INSTALL_DIRECTORY is not writeable by this script.
Please either change the directory permissions or override the
installation directory with the flag \"kurl-install-directory\"."
    fi
    rm "$tmpfile"
    pushd "$KURL_INSTALL_DIRECTORY" 1>/dev/null
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

function get_skip_system_package_install_flag() {
    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" != "1" ]; then
        return
    fi
    echo " skip-system-package-install"
}

function get_exclude_builtin_host_preflights_flag() {
    if [ "${EXCLUDE_BUILTIN_HOST_PREFLIGHTS}" != "1" ]; then
        return
    fi
    echo " exclude-builtin-host-preflights"
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
    local control_plane_label=
    control_plane_label="$(kubernetes_get_control_plane_label)"
    while read -r primary; do
        printf " primary-host=$primary"
    done < <(kubectl get nodes --no-headers --selector="$control_plane_label" -owide | awk '{ print $6 }')

    while read -r secondary; do
        printf " secondary-host=$secondary"
    done < <(kubectl get node --no-headers --selector='!'"$control_plane_label" -owide | awk '{ print $6 }')
}

function get_ipv6_flag() {
    if [ "$IPV6_ONLY" = "1" ]; then
        echo " ipv6"
    fi
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

    if [ "$newPid" = "0" ]; then
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

    logSubstep "Restarting $serviceName..."
    systemctl restart $serviceName

    log "Checking if $serviceName was restarted successfully"
    if ! spinner_until 120 systemd_restart_succeeded $pid $serviceName; then
        journalctl -xe
        bail "Could not successfully restart systemd service $serviceName"
    fi

    logSuccess "Service $serviceName restarted."
}

# returns true when a job has completed
function job_is_completed() {
  local namespace="$1"
  local jobName="$2"
  kubectl get jobs -n "$namespace" "$jobName" | grep -q '1/1'
}

function maybe() {
    local cmd="$1"
    local args=( "${@:2}" )

    $cmd "${args[@]}" 2>/dev/null || true
}

MACHINE_ID=
KURL_INSTANCE_UUID=
function get_machine_id() {
    MACHINE_ID="$(${DIR}/bin/kurl host protectedid || true)"
    if [ -f /etc/kurl/uuid ]; then
        KURL_INSTANCE_UUID="$(cat /etc/kurl/uuid)"
    else
        if [ -f "${KURL_INSTALL_DIRECTORY}/uuid" ]; then
            KURL_INSTANCE_UUID="$(cat ${KURL_INSTALL_DIRECTORY}/uuid)"
            rm -f "${KURL_INSTALL_DIRECTORY}/uuid"
        else
            KURL_INSTANCE_UUID=$(< /dev/urandom tr -dc a-z0-9 | head -c32)
        fi
        # use /etc/kurl to persist the instance id "machine id" across cluster reset
        mkdir -p /etc/kurl
        echo "$KURL_INSTANCE_UUID" > /etc/kurl/uuid
    fi
}

function kebab_to_camel() {
    echo "$1" | sed -E 's/-(.)/\U\1/g'
}

function build_installer_prefix() {
    local installer_id="$1"
    local kurl_version="$2"
    local kurl_url="$3"
    local proxy_address="$4"
    local proxy_https_address="$5"

    if [ -z "${kurl_url}" ]; then
        echo "cat "
        return
    fi

    local is_https=
    local curl_flags=
    if [ -n "${proxy_address}" ] || [ -n "${proxy_https_address}" ]; then
        curl_flags=" -x ${proxy_address}"
        is_https=$(echo "${kurl_url}" | grep -q "^https" && echo "true" || echo "false")
        if [ -n "${proxy_https_address}" ] && [ "$is_https" = "true" ]; then
            curl_flags=" -x ${proxy_https_address}"
        fi
    fi

    if [ -n "${kurl_version}" ]; then
        echo "curl -fsSL${curl_flags} ${kurl_url}/version/${kurl_version}/${installer_id}/"
    else
        echo "curl -fsSL${curl_flags} ${kurl_url}/${installer_id}/"
    fi
}

# get_local_node_name returns the name of the current node.
function get_local_node_name() {
    echo "$HOSTNAME"
}

# this waits for a deployment to have all replicas up-to-date and available
function deployment_fully_updated() {
    x_fully_updated "$1" deployment "$2"
}

# this waits for a statefulset to have all replicas up-to-date and available
function statefulset_fully_updated() {
    x_fully_updated "$1" statefulset "$2"
}

# this waits for a resource type (deployment or statefulset) to have all replicas up-to-date and available
function x_fully_updated() {
    local namespace=$1
    local resourcetype=$2
    local name=$3

    local desiredReplicas
    desiredReplicas=$(kubectl get $resourcetype -n "$namespace" "$name" -o jsonpath='{.status.replicas}')

    local availableReplicas
    availableReplicas=$(kubectl get $resourcetype -n "$namespace" "$name" -o jsonpath='{.status.availableReplicas}')

    local readyReplicas
    readyReplicas=$(kubectl get $resourcetype -n "$namespace" "$name" -o jsonpath='{.status.readyReplicas}')

    local updatedReplicas
    updatedReplicas=$(kubectl get $resourcetype -n "$namespace" "$name" -o jsonpath='{.status.updatedReplicas}')

    if [ "$desiredReplicas" != "$availableReplicas" ] ; then
        return 1
    fi

    if [ "$desiredReplicas" != "$readyReplicas" ] ; then
        return 1
    fi

    if [ "$desiredReplicas" != "$updatedReplicas" ] ; then
        return 1
    fi

    return 0
}

# this waits for a daemonset to have all replicas up-to-date and available
function daemonset_fully_updated() {
    local namespace=$1
    local daemonset=$2

    local desiredNumberScheduled
    desiredNumberScheduled=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.desiredNumberScheduled}')

    local currentNumberScheduled
    currentNumberScheduled=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.currentNumberScheduled}')

    local numberAvailable
    numberAvailable=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.numberAvailable}')

    local numberReady
    numberReady=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.numberReady}')

    local updatedNumberScheduled
    updatedNumberScheduled=$(kubectl get daemonset -n "$namespace" "$daemonset" -o jsonpath='{.status.updatedNumberScheduled}')

    if [ "$desiredNumberScheduled" != "$numberAvailable" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$currentNumberScheduled" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$numberAvailable" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$numberReady" ] ; then
        return 1
    fi

    if [ "$desiredNumberScheduled" != "$updatedNumberScheduled" ] ; then
        return 1
    fi

    return 0
}

# pods_gone_by_selector returns true if there are no pods matching the given selector
function pods_gone_by_selector() {
    local namespace=$1
    local selector=$2
    [ "$(pod_count_by_selector "$namespace" "$selector")" = "0" ]
}

# pod_count_by_selector returns the number of pods matching the given selector or -1 if the command fails
function pod_count_by_selector() {
    local namespace=$1
    local selector=$2

    local pods=
    if ! pods="$(kubectl -n "$namespace" get pods --no-headers -l "$selector" 2>/dev/null)" ; then
        echo -1
    fi

    echo -n "$pods" | wc -l
}

# retag_gcr_images takes every k8s.gcr.io image and adds a registry.k8s.io alias if it does not already exist
# and vice versa
function retag_gcr_images() {
    local images=
    local image=
    local new_image=
    if [ -n "$DOCKER_VERSION" ]; then
        images=$(docker images --format '{{.Repository}}:{{.Tag}}' | { grep -F k8s.gcr.io || true; })
        for image in $images ; do
            new_image="${image//k8s.gcr.io/registry.k8s.io}"
            docker tag "$image" "$new_image" 2>/dev/null || true
            # if the image name matches `coredns`, extract the tag and also retag `$image` to registry.k8s.io/coredns:$tag
            # this handles issues where kubernetes expects coredns to be at registry.k8s.io/coredns:1.6.2 but it is at registry.k8s.io/coredns/coredns:v1.6.2
            if [[ "$image" =~ "coredns" ]]; then
                tag=$(echo "$image" | awk -F':' '{print $2}')
                docker tag "$image" "registry.k8s.io/coredns:$tag" 2>/dev/null || true
            fi
        done
        images=$(docker images --format '{{.Repository}}:{{.Tag}}' | { grep -F registry.k8s.io || true; })
        for image in $images ; do
            new_image="${image//registry.k8s.io/k8s.gcr.io}"
            docker tag "$image" "$new_image" 2>/dev/null || true
        done
    else
        images=$(ctr -n=k8s.io images list --quiet | { grep -F k8s.gcr.io || true; })
        for image in $images ; do
            new_image="${image//k8s.gcr.io/registry.k8s.io}"
            ctr -n k8s.io images tag "$image" "$new_image" 2>/dev/null || true
            # if the image name matches `coredns`, extract the tag and also retag `$image` to registry.k8s.io/coredns:$tag
            # this handles issues where kubernetes expects coredns to be at registry.k8s.io/coredns:1.6.2 but it is at registry.k8s.io/coredns/coredns:v1.6.2
            if [[ "$image" =~ "coredns" ]]; then
                tag=$(echo "$image" | awk -F':' '{print $2}')
                ctr -n k8s.io images tag "$image" "registry.k8s.io/coredns:$tag" 2>/dev/null || true
            fi
        done
        images=$(ctr -n=k8s.io images list --quiet | { grep -F registry.k8s.io || true; })
        for image in $images ; do
            new_image="${image//registry.k8s.io/k8s.gcr.io}"
            ctr -n k8s.io images tag "$image" "$new_image" 2>/dev/null || true
        done
    fi
}

function canonical_image_name() {
    local image="$1"
    if echo "$image" | grep -vq '/' ; then
        image="library/$image"
    fi
    if echo "$image" | awk -F'/' '{print $1}' | grep -vq '\.' ; then
        image="docker.io/$image"
    fi
    if echo "$image" | grep -vq ':' ; then
        image="$image:latest"
    fi
    echo "$image"
}

# check_for_running_pods scans for pod(s) in a namespace and checks whether their status is running/completed
# note: Evicted pods are exempt from this check
# exports a variable UNHEALTHY_PODS containing the names of pods that are not running/completed
UNHEALTHY_PODS=
function check_for_running_pods() {
    local namespace=$1
    local is_job_controller=0
    local ns_pods=
    local status=
    local containers=

    local unhealthy_podnames=

    ns_pods=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}')

    if [ -z "$ns_pods" ]; then
        return 0
    fi

    for pod in $ns_pods; do
        status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}')

        # ignore pods that have been Evicted
        if [ "$status" == "Failed" ] && [[ $(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.reason}') == "Evicted" ]]; then
            continue
        fi

        if [ "$status" == "Succeeded" ]; then
            continue
        fi

        if [ "$status" != "Running" ]; then
            unhealthy_podnames="$unhealthy_podnames $pod"
            continue
        fi

        containers=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[*].name}")
        for container in $containers; do
            container_status=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.status.containerStatuses[?(@.name==\"$container\")].ready}")
            
            if [ "$container_status" != "true" ]; then
                unhealthy_podnames="$unhealthy_podnames $pod"
                continue
            fi
        done
    done

    # if there are unhealthy pods, return 1
    if [ -n "$unhealthy_podnames" ]; then
        export UNHEALTHY_PODS="$unhealthy_podnames"
        return 1
    fi

    return 0
}

# retry a command if it fails up to $1 number of times
# Usage: cmd_retry 3 curl --globoff --noproxy "*" --fail --silent --insecure https://10.128.0.25:6443/healthz
function cmd_retry() {
    local retries=$1
    shift

    local count=0
    until "$@"; do
        exit=$?
        wait=$((2 ** $count))
        count=$(($count + 1))
        if [ $count -lt $retries ]; then
            echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
            sleep $wait
        else
            echo "Retry $count/$retries exited $exit, no more retries left."
            return $exit
        fi
    done
    return 0
}

# common_upgrade_step_versions returns a list of upgrade steps that need to be performed, based on
# the supplied space-delimited set of step versions, for use by other functions.
# e.g. "1.5.12\n1.6.11\n1.7.11"
function common_upgrade_step_versions() {
    local step_versions=
    read -ra step_versions <<< "$1"
    local from_version=$2
    local desired_version=$3

    local to_version=
    to_version=$(common_upgrade_version_to_major_minor "$desired_version")

    # check that major versions are the same
    local first_major=
    first_major=$(common_upgrade_major_minor_to_major "$from_version")
    local last_major=
    last_major=$(common_upgrade_major_minor_to_major "$to_version")
    if [ "$first_major" != "$last_major" ]; then
        bail "Upgrade accross major version from $from_version to $to_version is not supported."
    fi

    local first_minor=
    local last_minor=
    first_minor=$(common_upgrade_major_minor_to_minor "$from_version")
    first_minor=$((first_minor + 1)) # exclusive of from_version
    last_minor=$(common_upgrade_major_minor_to_minor "$to_version")

    if [ "${#step_versions[@]}" -le "$last_minor" ]; then
        bail "Upgrade from $from_version to $to_version is not supported."
    fi

    # if there are no steps to perform, return
    if [ "$first_minor" -gt "$last_minor" ]; then
        return
    fi

    if [ "$desired_version" != "$to_version" ]; then
        last_minor=$((last_minor - 1)) # last version is the desired version
    fi

    local step=
    for (( step=first_minor ; step<=last_minor ; step++ )); do
        echo "${step_versions[$step]}"
    done
    if [ "$desired_version" != "$to_version" ]; then
        echo "$desired_version"
    fi
}

# common_upgrade_compare_versions prints 0 if the versions are equal, 1 if the first is greater,
# and -1 if the second is greater.
function common_upgrade_compare_versions() {
    local a="$1"
    local b="$2"

    local a_major=
    local b_major=
    a_major=$(common_upgrade_major_minor_to_major "$a")
    b_major=$(common_upgrade_major_minor_to_major "$b")

    if [ "$a_major" -lt "$b_major" ]; then
        echo "-1"
        return
    elif [ "$a_major" -gt "$b_major" ]; then
        echo "1"
        return
    fi

    local a_minor=
    local b_minor=
    a_minor=$(common_upgrade_major_minor_to_minor "$a")
    b_minor=$(common_upgrade_major_minor_to_minor "$b")

    if [ "$a_minor" -lt "$b_minor" ]; then
        echo "-1"
        return
    elif [ "$a_minor" -gt "$b_minor" ]; then
        echo "1"
        return
    fi

    echo "0"
}

# common_upgrade_is_version_included returns 0 if the version is included in the range.
function common_upgrade_is_version_included() {
    local from_version="$1"
    local to_version="$2"
    local current_version="$3"
    # if current_version is greater than from_version and current_version is less than or equal to to_version
    [ "$(common_upgrade_compare_versions "$current_version" "$from_version")" = "1" ] && \
    [ "$(common_upgrade_compare_versions "$current_version" "$to_version")" != "1" ]
}

# common_upgrade_max_version will return the greater of the two versions.
function common_upgrade_max_version() {
    local a="$1"
    local b="$2"
    if [ "$(common_upgrade_compare_versions "$a" "$b")" = "1" ]; then
        echo "$a"
    else
        echo "$b"
    fi
}

# common_upgrade_print_list_of_minor_upgrades prints message of minor versions that will be
# upgraded. e.g. "1.0.x to 1.1, 1.1 to 1.2, 1.2 to 1.3, and 1.3 to 1.4"
function common_upgrade_print_list_of_minor_upgrades() {
    local from_version="$1"
    local to_version="$2"

    printf "This involves upgrading from "
    local first_minor=
    local last_minor=
    first_minor=$(common_upgrade_major_minor_to_minor "$from_version")
    last_minor=$(common_upgrade_major_minor_to_minor "$to_version")

    local minor=
    for (( minor=first_minor ; minor<last_minor ; minor++ )); do
        if [ "$minor" -gt "$first_minor" ]; then
            printf ", "
            if [ "$((minor + 1))" -eq "$last_minor" ]; then
                printf "and "
            fi
        fi
        printf "1.%s to 1.%s" "$minor" "$((minor + 1))"
    done
    printf ".\n"
}

# common_upgrade_major_minor_to_major returns the major version of a major.minor version.
function common_upgrade_major_minor_to_major() {
    echo "$1" | cut -d. -f1
}

# common_upgrade_major_minor_to_minor returns the minor version of a major.minor version.
function common_upgrade_major_minor_to_minor() {
    echo "$1" | cut -d. -f2
}

# common_upgrade_version_to_major_minor returns the major.minor version of a semver version.
function common_upgrade_version_to_major_minor() {
    echo "$1" | cut -d. -f1,2
}

# common_upgrade_major_minor_less_one returns the major.minor version less one minor.
function common_upgrade_major_minor_less_one() {
    local major=
    major="$(common_upgrade_major_minor_to_major "$1")"
    local minor=
    minor="$(common_upgrade_major_minor_to_minor "$1")"
    if [ "$minor" != "0" ]; then
        minor="$((minor - 1))"
    fi
    echo "$major.$minor"
}

# common_list_images_in_manifest_file will list images in the given manifest file.
function common_list_images_in_manifest_file() {
    local manifest_file="$1"

    local image_list=
    for image in $(grep "^image " "$manifest_file" | awk '{print $3}' | tr '\n' ' ') ; do
        image_list=$image_list" $(canonical_image_name "$image")"
    done
    echo "$image_list" | xargs # trim whitespace
}

# common_upgrade_merge_images_list will merge each list of images from the arguments into a single
# list and deduplicate the list.
function common_upgrade_merge_images_list() {
    local images_list=
    local list=
    for list in "$@" ; do
        images_list="$images_list $list"
    done
    echo "$images_list" | tr " " "\n" | sort | uniq | tr "\n" " " | xargs
}

# common_upgrade_storage_check verifies that enough disk space exists based on the archive size and
# multipliers.
function common_upgrade_storage_check() {
    local archive_size="$1"
    local multiplier_files="$2"
    local multiplier_images="$3"
    local upgrade_name="$4"

    local container_directory=
    if [ -n "$DOCKER_VERSION" ]; then
        container_directory="/var/lib/docker"
    else
        container_directory="/var/lib/containerd"
    fi

    # if $container_directory and $KURL_INSTALL_DIRECTORY are on the same filesystem, we need to check that there is space for all of the files
    if [ "$(df -P "$container_directory" | awk 'END{print $1}')" = "$(df -P "$KURL_INSTALL_DIRECTORY" | awk 'END{print $1}')" ]; then
        local total_required_size=
        local total_multiplier=$((multiplier_files + multiplier_images))
        total_required_size=$((archive_size * total_multiplier))

        local free_kb=
        local free_mb=
        free_kb="$(df -P "$KURL_INSTALL_DIRECTORY" | awk 'END{print $4}')"
        free_mb="$((free_kb / 1024))"

        local total_kb=
        local total_mb=
        total_kb="$(df -P "$KURL_INSTALL_DIRECTORY" | awk 'END{print $2}')"
        total_mb="$((total_kb / 1024))"

        local available_mb=
        available_mb="$((free_mb - total_mb * 3 / 20))" # free space, excluding 15% of the total

        if [ "$available_mb" -lt "$total_required_size" ]; then
            logWarn "Not enough disk space to upgrade $upgrade_name."
            logWarn "You need at least $total_required_size MB of free space on the filesystem containing $KURL_INSTALL_DIRECTORY and $container_directory - and to have 15%% free space after that to avoid image pruning."
            logWarn "Currently, only $available_mb MB of free space is available before reaching 85%% capacity."
            logWarn "If you have already loaded images or started this $upgrade_name upgrade, it is possible that less space will be required. Would you like to continue anyways?"
            if ! confirmN; then
                return 1
            fi
        fi
    else
        local kurl_dir_size=
        kurl_dir_size=$((archive_size * multiplier_files))

        local kurl_free_kb=
        local kurl_free_mb=
        kurl_free_kb="$(df -P "$KURL_INSTALL_DIRECTORY" | awk 'END{print $4}')"
        kurl_free_mb="$((kurl_free_kb / 1024))"

        if [ "$kurl_free_mb" -lt "$kurl_dir_size" ]; then
            logWarn "Not enough disk space to upgrade $upgrade_name."
            logWarn "You need at least $kurl_dir_size MB of free space on the filesystem containing $KURL_INSTALL_DIRECTORY."
            logWarn "Currently, only $kurl_free_mb MB of free space is available."
            logWarn "If you have already loaded images or started this $upgrade_name upgrade, it is possible that less space will be required. Would you like to continue anyways?"
            if ! confirmN; then
                return 1
            fi
        fi

        local container_dir_size=
        container_dir_size=$((archive_size * multiplier_images))

        local container_free_kb=
        local container_free_mb=
        container_free_kb="$(df -P "$KURL_INSTALL_DIRECTORY" | awk 'END{print $4}')"
        container_free_mb="$((container_free_kb / 1024))"

        local container_total_kb=
        local container_total_mb=
        container_total_kb="$(df -P "$KURL_INSTALL_DIRECTORY" | awk 'END{print $2}')"
        container_total_mb="$((container_total_kb / 1024))"

        local container_available_mb=
        container_available_mb="$((container_free_mb - container_total_mb * 3 / 20))" # free space, excluding 15% of the total

        if [ "$container_available_mb" -lt "$container_dir_size" ]; then
            logWarn "Not enough disk space to upgrade $upgrade_name."
            logWarn "You need at least $container_dir_size MB of free space on the filesystem containing $container_directory - and to have 15%% free space after that to avoid image pruning."
            logWarn "Currently, only $container_available_mb MB of free space is available before reaching 85%% capacity."
            logWarn "If you have already loaded images or started this $upgrade_name upgrade, it is possible that less space will be required. Would you like to continue anyways?"
            if ! confirmN; then
                return 1
            fi
        fi
    fi
}

# common_task_require_param requires that the given parameter is set or bails.
function common_task_require_param() {
    local param="$1"
    local value="$2"
    if [ -z "$value" ]; then
        bail "Error: $param is required"
    fi
}

# common_upgrade_tasks_params parses the parameters for the rook upgrade tasks.
function common_upgrade_tasks_params() {
    while [ "$1" != "" ]; do
        local _param=
        local _value=
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            from-version)
                from_version="$_value"
                ;;
            to-version)
                to_version="$_value"
                ;;
            airgap)
                airgap="1"
                ;;
            *)
                bail "Error: unknown parameter \"$_param\""
                ;;
        esac
        shift
    done
}

# common_prompt_missing_assets prompts the user to run the command to load the assets on the given
# remote nodes before proceeding.
function common_prompt_task_missing_assets() {
    local nodes="$1"
    local from_version="$2"
    local to_version="$3"
    local upgrade_name="$4"
    local task="$5"

    if [ -z "$nodes" ]; then
        return
    fi

    local prefix=
    if [ "$AIRGAP" = "1" ]; then
        prefix="cat ./"
    else
        prefix="$(build_installer_prefix "$INSTALLER_ID" "$KURL_VERSION" "$KURL_URL" "$PROXY_ADDRESS" "$PROXY_HTTPS_ADDRESS")"
    fi

    local airgap_flag=
    if [ "$AIRGAP" = "1" ]; then
        airgap_flag="airgap"
    fi

    printf "The node(s) %s appear to be missing assets required for the %s upgrade from %s to %s.\n" \
        "$(echo "$nodes" | tr '\n' ' ' | xargs)" "$upgrade_name" "$from_version" "$to_version"
    printf "Please run the following on each of these nodes before continuing:\n"

    local command=
    command=$(printf "%stasks.sh | sudo bash -s %s from-version=%s to-version=%s %s" "$prefix" "$task" "$from_version" "$to_version" "$airgap_flag")

    for node in $nodes; do
        echo "$command" > "$DIR/remotes/$node"
    done

    printf "\n\t%b%s %b\n\n" \
        "$GREEN" "$command" "$NC"
    printf "Are you ready to continue? "
    confirmY
}

# node_is_using_docker returns 0 if the current node is using docker as the container runtime.
function node_is_using_docker() {
    local node
    node="$(get_local_node_name)"
    kubectl get node "$node" -ojsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/cri-socket}' | grep -q "dockershim.sock"
}

# get_ekco_addr prints the service address (including port) for reaching the EKCO service to stdout
function get_ekco_addr() {
    if [ -n "$EKCO_ADDRESS" ]; then
        echo "$EKCO_ADDRESS"
        return
    fi

    local ekco_addr=
    local ekco_port=
    local ekco_service_ip=
    ekco_service_ip=$(kubectl get svc ekc-operator -n kurl -o jsonpath='{.spec.clusterIP}')
    ekco_port=$(kubectl get svc ekc-operator -n kurl -o jsonpath='{.spec.ports[?(@.nodePort)].port}')
    ekco_addr="${ekco_service_ip}:${ekco_port}"
    echo "$ekco_addr"
}

# get_ekco_storage_migration_auth_token prints the ekco storage migration authentication token to stdout
function get_ekco_storage_migration_auth_token() {
    if [ -n "$EKCO_AUTH_TOKEN" ]; then
        echo "$EKCO_AUTH_TOKEN"
        return
    fi

    local auth_token=
    auth_token=$(kubectl get cm -n kurl ekco-config -ojsonpath='{.data.config\.yaml}' | grep "storage_migration_auth_token:" | awk '{print $2}')

    echo "$auth_token"
}

# determine storage migration ready timeout
function storage_migration_ready_timeout() {
    if [ -z "$STORAGE_MIGRATION_READY_TIMEOUT" ]; then
        STORAGE_MIGRATION_READY_TIMEOUT="10m0s"
    fi
    echo "$STORAGE_MIGRATION_READY_TIMEOUT"
}

# return the version of kubernetes that is currently installed on the server
function kubectl_server_version() {
    local kubectl_server_version=
    if kubectl version --short > /dev/null 2>&1 ; then
        kubectl_server_version="$(kubectl version --short | grep -i server | awk '{ print $3 }')"
    else
        # kubectl version --short is not supported in kubectl > 1.27, but is now the default behavior
        kubectl_server_version="$(kubectl version | grep -i server | awk '{ print $3 }')"
    fi
    echo "$kubectl_server_version"
}

# return the version of kubernetes that is currently installed on the client
function kubectl_client_version() {
    local kubectl_client_version=
    if kubectl version --short > /dev/null 2>&1 ; then
        kubectl_client_version="$(kubectl version --short | grep -i client | awk '{ print $3 }')"
    else
        # kubectl version --short is not supported in kubectl > 1.27, but is now the default behavior
        kubectl_client_version="$(kubectl version | grep -i client | awk '{ print $3 }')"
    fi
    echo "$kubectl_client_version"
}

# create directories for remote commands to be placed within, and ensure they are empty
function setup_remote_commands_dirs() {
    mkdir -p "$DIR/remotes"
    rm -f "$DIR/remotes/*"
}
