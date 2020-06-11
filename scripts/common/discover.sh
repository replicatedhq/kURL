
function discover() {
    detectLsbDist
    discoverCurrentKubernetesVersion

    # never upgrade docker underneath kubernetes
    if docker version >/dev/null 2>&1 ; then
        SKIP_DOCKER_INSTALL=1
        echo "Docker already exists on this machine so no docker install will be performed"
    fi

    if ctr --version >/dev/null 2>&1 ; then
        SKIP_CONTAINERD_INSTALL=1
        echo "Containerd already exists on this machine so no containerd install will be performed"
    fi

    discoverPublicIp
    discover_private_ip

    KERNEL_MAJOR=$(uname -r | cut -d'.' -f1)
    KERNEL_MINOR=$(uname -r | cut -d'.' -f2)
}
 
LSB_DIST=
DIST_VERSION=
DIST_VERSION_MAJOR=
detectLsbDist() {
    _dist=
    _error_msg="We have checked /etc/os-release and /etc/centos-release files."
    if [ -f /etc/centos-release ] && [ -r /etc/centos-release ]; then
        # CentOS 6 example: CentOS release 6.9 (Final)
        # CentOS 7 example: CentOS Linux release 7.5.1804 (Core)
        _dist="$(cat /etc/centos-release | cut -d" " -f1)"
        _version="$(cat /etc/centos-release | sed 's/Linux //' | cut -d" " -f3 | cut -d "." -f1-2)"
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
            _version=`awk '/Amazon Linux/{print $NF}' /etc/system-release`
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
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
                ;;
            centos)
                _error_msg="$_error_msg\nHowever detected version $_version is less than 6."
                oIFS="$IFS"; IFS=.; set -- $_version; IFS="$oIFS";
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
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
                [ $1 -ge 6 ] && LSB_DIST=$_dist && DIST_VERSION=$_version && DIST_VERSION_MAJOR=$1
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
        echo >&2 "  https://help.replicated.com/docs/distributing-an-application/installing/"
        exit 1
    fi
}

discoverCurrentKubernetesVersion() {
    set +e
    CURRENT_KUBERNETES_VERSION=$(cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | grep image: | grep -oE '[0-9]+.[0-9]+.[0-9]')
    set -e

    if [ -n "$CURRENT_KUBERNETES_VERSION" ]; then
        semverParse $CURRENT_KUBERNETES_VERSION
        KUBERNETES_CURRENT_VERSION_MAJOR="$major"
        KUBERNETES_CURRENT_VERSION_MINOR="$minor"
        KUBERNETES_CURRENT_VERSION_PATCH="$patch"

        semverParse "$KUBERNETES_VERSION"

        if [ "$KUBERNETES_CURRENT_VERSION_MINOR" -gt "$minor" ]; then
            printf "%s %s %s" \
                   "The currently installed kubernetes version is ${CURRENT_KUBERNETES_VERSION}." \
                   "The requested version to upgrade to is ${KUBERNETES_VERSION}." \
                   "Since the currently installed version is newer than the requested version, no action will be taken."
            bail
        fi

        NEXT_UPGRADEABLE_VERSION_MINOR="$(($KUBERNETES_CURRENT_VERSION_MINOR + 1))"

        if [ "$NEXT_UPGRADEABLE_VERSION_MINOR" -lt $minor ]; then
            printf "%s %s %s" \
                   "The currently installed kubernetes version is ${CURRENT_KUBERNETES_VERSION}." \
                   "The requested version to upgrade to is ${KUBERNETES_VERSION}." \
                   "kURL can only be upgrade one minor version at at time. Please install ${major}.${NEXT_UPGRADEABLE_VERSION_MINOR}.X. first."
            bail
        fi

        if [ "$KUBERNETES_CURRENT_VERSION_MINOR" -lt "$minor" ]; then
            KUBERNETES_UPGRADE=1
            KUBERNETES_UPGRADE_LOCAL_MASTER_MINOR=1
            if kubernetes_any_remote_master_unupgraded; then
                KUBERNETES_UPGRADE=1
                KUBERNETES_UPGRADE_REMOTE_MASTERS_MINOR=1
            fi

            if kubernetes_any_worker_unupgraded; then
                KUBERNETES_UPGRADE=1
                KUBERNETES_UPGRADE_WORKERS_MINOR=1
            fi
        elif [ "$KUBERNETES_CURRENT_VERSION_PATCH" -lt "$patch" ]; then
            KUBERNETES_UPGRADE=1
            KUBERNETES_UPGRADE_LOCAL_MASTER_PATCH=1
            if kubernetes_any_remote_master_unupgraded; then
                KUBERNETES_UPGRADE=1
                KUBERNETES_UPGRADE_REMOTE_MASTERS_PATCH=1
            fi

            if kubernetes_any_worker_unupgraded; then
                KUBERNETES_UPGRADE=1
                KUBERNETES_UPGRADE_WORKERS_PATCH=1
            fi
        fi
    fi

    local _ifs="$IFS"
}

getDockerVersion() {
	if ! commandExists "docker"; then
		return
	fi
	DOCKER_VERSION=$(docker -v | awk '{gsub(/,/, "", $3); print $3}')
}

discoverPublicIp() {
    # gce
    set +e
    _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null)
    _status=$?
    set -e
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        PUBLIC_ADDRESS=$_out
        return
    fi

    # ec2
    set +e
    _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    _status=$?
    set -e
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        PUBLIC_ADDRESS=$_out
        return
    fi

    # azure
    set +e
    _out=$(curl --noproxy "*" --max-time 5 --connect-timeout 2 -qSfs -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text" 2>/dev/null)
    _status=$?
    set -e
    if [ "$_status" -eq "0" ] && [ -n "$_out" ]; then
        PUBLIC_ADDRESS=$_out
        return
    fi
}

function discover_private_ip() {
    if [ -n "$PRIVATE_ADDRESS" ]; then
        return 0
    fi
    PRIVATE_ADDRESS=$(cat /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null | grep advertise-address | awk -F'=' '{ print $2 }')
}
