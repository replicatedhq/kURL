
function install_host_archives() {
    local dir="$1"
    local dir_prefix="/archives"
    local packages=("${@:2}")
    _install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function install_host_packages() {
    local dir="$1"
    local dir_prefix=""
    local packages=("${@:2}")
    _install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function _install_host_packages() {
    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    case "$LSB_DIST" in
        ubuntu)
            _dpkg_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            ;;

        centos|rhel|amzn|ol)
            _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            ;;

        *)
            bail "Host package install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
            ;;
    esac
}

function dpkg_install_host_archives() {
    local dir="$1"
    local dir_prefix="/archives"
    local packages=("${@:2}")
    _dpkg_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function dpkg_install_host_packages() {
    local dir="$1"
    local dir_prefix=""
    local packages=("${@:2}")
    _dpkg_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function _dpkg_install_host_packages() {
    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    logStep "Installing host packages ${packages[*]}"

    local fullpath=
    fullpath="${dir}/ubuntu-${DIST_VERSION}${dir_prefix}"
    if ! test -n "$(shopt -s nullglob; echo "${fullpath}"/*.deb)" ; then
        echo "Will not install host packages ${packages[*]}, no packages found."
        return 0
    fi

    DEBIAN_FRONTEND=noninteractive dpkg --install --force-depends-version --force-confold "${fullpath}"/*.deb

    logSuccess "Host packages ${packages[*]} installed"
}

function yum_install_host_archives() {
    local dir="$1"
    local dir_prefix="/archives"
    local packages=("${@:2}")
    _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function yum_install_host_packages() {
    local dir="$1"
    local dir_prefix=""
    local packages=("${@:2}")
    _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function _yum_install_host_packages() {
    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    logStep "Installing host packages ${packages[*]}"

    local fullpath=
    if [ "$DIST_VERSION_MAJOR" = "8" ]; then
        fullpath="$(realpath "${dir}")/rhel-8${dir_prefix}"
    else
        fullpath="$(realpath "${dir}")/rhel-7${dir_prefix}"
    fi
    if ! test -n "$(shopt -s nullglob; echo "${fullpath}/*.rpm")" ; then
        echo "Will not install host packages ${packages[*]}, no packages found."
        return 0
    fi
    cat > /etc/yum.repos.d/kurl.local.repo <<EOF
[kurl.local]
name=kURL Local Repo
baseurl=file://${fullpath}
enabled=1
gpgcheck=0
EOF
    # We always use the same repo and we are kinda abusing yum here so we have to clear the cache.
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    yum makecache --disablerepo=* --enablerepo=kurl.local

    # shellcheck disable=SC2086
    yum --disablerepo=* --enablerepo=kurl.local install -y "${packages[@]}"
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    rm /etc/yum.repos.d/kurl.local.repo

    logSuccess "Host packages ${packages[*]} installed"
}
