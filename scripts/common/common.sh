
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
    chmod 444 /etc/kubernetes/admin.conf
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

function load_images() {
    find "$1" -type f | xargs -I {} bash -c "docker load < {}"
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
    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        curl -sSOL $KURL_URL/dist/common.tar.gz 
        tar xf common.tar.gz
        rm common.tar.gz
    fi
    if [ -f shared/kurl-util.tar ]; then
        docker load < shared/kurl-util.tar
    fi
}

splitHostPort() {
    oIFS="$IFS"; IFS=":" read -r HOST PORT <<< "$1"; IFS="$oIFS"
}
