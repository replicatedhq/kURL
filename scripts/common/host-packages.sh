
function install_host_packages() {
    local dir="$1"
    shift
    _install_host_packages "$dir" "" "$@"
}

function install_host_archives() {
    local dir="$1"
    shift
    _install_host_packages "$dir" "/archives" "$@"
}

function _install_host_packages() {
    local dir="$1"
    local dir_prefix="$2"
    shift
    shift
    local packages=("$@")

    logStep "Installing host packages ${packages[*]}"

    case "$LSB_DIST" in
        ubuntu)
            local fullpath=
            fullpath="${dir}/ubuntu-${DIST_VERSION}${dir_prefix}/*.deb"
            if test -n "$(shopt -s nullglob; echo "${fullpath}")" ; then
                DEBIAN_FRONTEND=noninteractive dpkg --install --force-depends-version --force-confold "${fullpath}"
            fi
            ;;

        centos|rhel|amzn|ol)
            _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            ;;

        *)
            bail "Host package install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
            ;;
    esac

    logSuccess "Host packages ${packages[*]} installed"
}

function _yum_install_host_packages() {
    local fullpath=
    if [[ "$DIST_VERSION" =~ ^8 ]]; then
        fullpath="$(realpath "${dir}")/rhel-8${dir_prefix}"
    else
        fullpath="$(realpath "${dir}")/rhel-7${dir_prefix}"
    fi
    if ! test -n "$(shopt -s nullglob; echo "${fullpath}/*.rpm")" ; then
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
    # This is probably not great and probably has some undesirable effects.
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    yum makecache --disablerepo=* --enablerepo=kurl.local

    local filtered=
    filtered="$(yum_filter_host_packages kurl.local "${packages[@]}")"

    # shellcheck disable=SC2086
    yum --disablerepo=* --enablerepo=kurl.local install -y ${filtered}
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    rm /etc/yum.repos.d/kurl.local.repo
}

# yum_filter_host_packages will filter out packages not included in this distro
function yum_filter_host_packages() {
    local repo="$1"
    local packages=("$@")
    packages=("${packages[@]:1}")

    local available=
    available="$(yum -q list available --disablerepo=* --enablerepo="${repo}" | awk 'NR>1 {print $1}' | sed 's/\.[^\.]*$//g')"

    for i in "${!packages[@]}" ; do
        ! echo "${available}" | grep -q "^${packages[$i]}$" && unset -v 'packages[$i]'
    done
    echo "${packages[@]}"
}
