#!/bin/bash

function discover() {
    local fullCluster="$1"

    detectLsbDist
    discoverCurrentKubernetesVersion "$fullCluster"

    # never upgrade docker underneath kubernetes
    if docker version >/dev/null 2>&1 ; then
        SKIP_DOCKER_INSTALL=1
        if [ -n "$DOCKER_VERSION" ]; then
            echo "Docker already exists on this machine so no docker install will be performed"
        fi
    fi

    discover_public_ip
    discover_private_ip

    KERNEL_MAJOR=$(uname -r | cut -d'.' -f1)
    KERNEL_MINOR=$(uname -r | cut -d'.' -f2)
}
 
LSB_DIST=
DIST_VERSION=
DIST_VERSION_MAJOR=
DIST_VERSION_MINOR=
detectLsbDist() {
    _dist=
    _error_msg="We have checked /etc/os-release and /etc/centos-release files."
    if [ -f /etc/centos-release ] && [ -r /etc/centos-release ]; then
        # CentOS 6 example: CentOS release 6.9 (Final)
        # CentOS 7 example: CentOS Linux release 7.5.1804 (Core)
        _dist="$(cat /etc/centos-release | cut -d" " -f1)"
        _version="$(cat /etc/centos-release | sed 's/Linux //' | sed 's/Stream //' | cut -d" " -f3 | cut -d "." -f1-2)"
    elif [ -f /etc/os-release ] && [ -r /etc/os-release ]; then
        _dist="$(. /etc/os-release && echo "$ID")"
        _version="$(. /etc/os-release && echo "$VERSION_ID")"
    elif [ -f /etc/redhat-release ] && [ -r /etc/redhat-release ]; then
        # this is for RHEL6
        _dist="rhel"
        _major_version=$(cat /etc/redhat-release | cut -d" " -f7 | cut -d "." -f1)
        _minor_version=$(cat /etc/redhat-release | cut -d" " -f7 | cut -d "." -f2)
        _version=$_major_version
    elif [ -f /etc/system-release ] && [ -r /etc/system-release ]; then
        if grep --quiet "Amazon Linux" /etc/system-release; then
            # Special case for Amazon 2014.03
            _dist="amzn"
            _version=$(awk '/Amazon Linux/{print $NF}' /etc/system-release)
        fi
    else
        _error_msg="$_error_msg\nDistribution cannot be determined because neither of these files exist."
    fi

    if [ -n "$_dist" ]; then
        _error_msg="$_error_msg\nDetected distribution is ${_dist}."
        _dist="$(echo "$_dist" | tr '[:upper:]' '[:lower:]')"
        case "$_dist" in
            ubuntu)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 12."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 12 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            debian)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 7."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 7 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            fedora)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 21."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 21 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            rhel)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 7."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1 && DIST_VERSION_MINOR="${DIST_VERSION#$DIST_VERSION_MAJOR.}" && DIST_VERSION_MINOR="${DIST_VERSION_MINOR%%.*}"
                ;;
            rocky)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 7."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1 && DIST_VERSION_MINOR="${DIST_VERSION#$DIST_VERSION_MAJOR.}" && DIST_VERSION_MINOR="${DIST_VERSION_MINOR%%.*}"
                ;;
            centos)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 6."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1 && DIST_VERSION_MINOR="${DIST_VERSION#$DIST_VERSION_MAJOR.}" && DIST_VERSION_MINOR="${DIST_VERSION_MINOR%%.*}"
                ;;
            amzn)
                _error_msg="$_error_msg\nHowever detected version $_version is not one of\n    2, 2.0, 2018.03, 2017.09, 2017.03, 2016.09, 2016.03, 2015.09, 2015.03, 2014.09, 2014.03."
                [ "$_version" = "2" ] || [ "$_version" = "2.0" ] || \
                [ "$_version" = "2018.03" ] || \
                [ "$_version" = "2017.03" ] || [ "$_version" = "2017.09" ] || \
                [ "$_version" = "2016.03" ] || [ "$_version" = "2016.09" ] || \
                [ "$_version" = "2015.03" ] || [ "$_version" = "2015.09" ] || \
                [ "$_version" = "2014.03" ] || [ "$_version" = "2014.09" ] && \
                LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$_version
                ;;
            sles)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 12."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 12 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            ol)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 6."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1 && DIST_VERSION_MINOR="${DIST_VERSION#$DIST_VERSION_MAJOR.}" && DIST_VERSION_MINOR="${DIST_VERSION_MINOR%%.*}"
                ;;
            *)
                _error_msg="$_error_msg\nThat is an unsupported distribution."
                ;;
        esac
    fi

    if [ -z "$LSB_DIST" ]; then
        echo >&2 "$(echo | sed "i$_error_msg")"
        echo >&2 ""
        echo >&2 "Please visit the following URL for more detailed installation instructions:"
        echo >&2 ""
        echo >&2 "  https://kurl.sh/docs/install-with-kurl/system-requirements"
        exit 1
    fi
}

export CURRENT_KUBERNETES_VERSION=

export KUBERNETES_UPGRADE=0

function discoverCurrentKubernetesVersion() {
    local fullCluster="$1"

    CURRENT_KUBERNETES_VERSION=$(maybe discover_local_kubernetes_version)

    if [ -z "$CURRENT_KUBERNETES_VERSION" ]; then
        # This is a new install and no upgrades are required
        return 0
    fi

    if [ -z "$fullCluster" ]; then
        return 0
    fi

    # Populate arrays with versions of remote nodes
    kubernetes_get_remote_primaries
    kubernetes_get_secondaries

    semverCompare "$CURRENT_KUBERNETES_VERSION" "$KUBERNETES_VERSION"
    if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
        KUBERNETES_UPGRADE=1
    elif [ "$SEMVER_COMPARE_RESULT" = "1" ]; then
        bail "The current Kubernetes version $CURRENT_KUBERNETES_VERSION is greater than target version $KUBERNETES_VERSION"
    fi

    # Check for upgrades required on remote primaries
    for node in "${!KUBERNETES_REMOTE_PRIMARIES[@]}"; do
        semverCompare "${KUBERNETES_REMOTE_PRIMARY_VERSIONS[$node]}" "$KUBERNETES_VERSION"
        if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
            KUBERNETES_UPGRADE=1
        elif [ "$SEMVER_COMPARE_RESULT" = "1" ]; then
            bail "The current Kubernetes version $CURRENT_KUBERNETES_VERSION is greater than target version $KUBERNETES_VERSION on remote primary $node"
        fi
    done

    # Check for upgrades required on remote secondaries
    for node in "${!KUBERNETES_SECONDARIES[@]}"; do
        semverCompare "${KUBERNETES_SECONDARY_VERSIONS[$node]}" "$KUBERNETES_VERSION"
        if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
            KUBERNETES_UPGRADE=1
        elif [ "$SEMVER_COMPARE_RESULT" = "1" ]; then
            bail "The current Kubernetes version $CURRENT_KUBERNETES_VERSION is greater than target version $KUBERNETES_VERSION on remote worker $node"
        fi
    done
}

function discover_local_kubernetes_version() {
    grep -s ' image: ' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

function get_docker_version() {
    if ! commandExists "docker" ; then
        return
    fi
    docker -v | awk '{gsub(/,/, "", $3); print $3}'
}

discover_public_ip() {
    if [ "$AIRGAP" == "1" ]; then
        return
    fi

    # gce
    set +e
    _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null)
    _status=$?
    set -e
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        if isValidIpv4 "$_out" || isValidIpv6 "$_out"; then
            PUBLIC_ADDRESS=$_out
        fi
        return
    fi

    # ec2
    set +e
    _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    _status=$?
    set -e
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        if isValidIpv4 "$_out" || isValidIpv6 "$_out"; then
            PUBLIC_ADDRESS=$_out
        fi
        return
    fi

    # azure
    set +e
    _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text" 2>/dev/null)
    _status=$?
    set -e
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        if isValidIpv4 "$_out" || isValidIpv6 "$_out"; then
            PUBLIC_ADDRESS=$_out
        fi
        return
    fi
}

function discover_private_ip() {
    if [ -n "$PRIVATE_ADDRESS" ]; then
        return 0
    fi
    PRIVATE_ADDRESS="$(${K8S_DISTRO}_discover_private_ip)"
}

function discover_non_loopback_nameservers() {
    local resolvConf=/etc/resolv.conf
    # https://github.com/kubernetes/kubernetes/blob/v1.19.3/cmd/kubeadm/app/componentconfigs/kubelet.go#L211
    if systemctl is-active -q systemd-resolved; then
        resolvConf=/run/systemd/resolve/resolv.conf
    fi
    cat $resolvConf | grep -E '^nameserver\s+' | grep -Eqv '^nameserver\s+127'
}
