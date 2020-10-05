
STORAGE_PROVISIONER=rook

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

bail() {
    logFail "$@"
    exit 1
}

waitForNodes() {
    n=0
    while ! kubectl get nodes >/dev/null 2>&1; do
        n="$(( $n + 1 ))"
        if [ "$n" -ge "120" ]; then
            # this should exit script on non-zero exit code and print error message
            kubectl get nodes 1>/dev/null
        fi
        sleep 2
    done
}

# Label nodes as provisioned by kurl installation
# (these labels should have been added by kurl installation.
#  See kubeadm-init and kubeadm-join yamk files.
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
    cp /etc/kubernetes/admin.conf $HOME/admin.conf
    chown $SUDO_USER:$SUDO_GID $HOME/admin.conf
    current_user_sudo_group
    if [ -n "$FOUND_SUDO_GROUP" ]; then
        chown root:$FOUND_SUDO_GROUP /etc/kubernetes/admin.conf
    fi
    chmod 440 /etc/kubernetes/admin.conf
    if ! grep -q "kubectl completion bash" /etc/profile; then
        echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile
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
    if [ -n "$DOCKER_VERSION" ]; then
        install_docker
        apply_docker_config
    elif [ -n "$CONTAINERD_VERSION" ]; then
        containerd_get_host_packages_online "$CONTAINERD_VERSION"
        . $DIR/addons/containerd/$CONTAINERD_VERSION/install.sh
        containerd_install
    fi
}

function load_images() {
    if [ -n "$DOCKER_VERSION" ]; then
        find "$1" -type f | xargs -I {} bash -c "docker load < {}"
    else
        find "$1" -type f | xargs -I {} bash -c "cat {} | gunzip | ctr -n=k8s.io images import -"
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
            $fn $args
            exit 1 # in case we're in a `set +e` state
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

function get_shared() {
    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        curl -sSOL $DIST_URL/common.tar.gz
        tar xf common.tar.gz
        rm common.tar.gz
    fi
    if [ -f shared/kurl-util.tar ]; then
        if [ -n "$DOCKER_VERSION" ]; then
            docker load < shared/kurl-util.tar
        else
            ctr -n=k8s.io images import shared/kurl-util.tar
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
            cp /etc/kubernetes/admin.conf $ownerdir/.kube/config
            chown -R $owner $ownerdir/.kube

            printf "To access the cluster with kubectl, ensure the KUBECONFIG environment variable is unset:\n"
            printf "\n"
            printf "${GREEN}    echo unset KUBECONFIG >> ~/.profile${NC}\n"
            printf "${GREEN}    bash -l${NC}\n"
            return
        fi
    fi

    printf "To access the cluster with kubectl, copy kubeconfig to your home directory:\n"
    printf "\n"
    printf "${GREEN}    cp /etc/kubernetes/admin.conf ~/.kube/config${NC}\n"
    printf "${GREEN}    chown -R ${owner} ~/.kube${NC}\n"
    printf "${GREEN}    echo unset KUBECONFIG >> ~/.profile${NC}\n"
    printf "${GREEN}    bash -l${NC}\n"
    printf "\n"
    printf "You will likely need to use sudo to copy and chown admin.conf.\n"
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
