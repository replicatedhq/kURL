
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

function rpm_force_install_host_archives() {
    local dir="$1"
    local dir_prefix="/archives"
    local packages=("${@:2}")
    _rpm_force_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function rpm_force_install_host_packages() {
    local dir="$1"
    local dir_prefix=""
    local packages=("${@:2}")
    _rpm_force_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
}

function _install_host_packages() {
    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    case "$LSB_DIST" in
        ubuntu)
            _dpkg_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            ;;

        centos|rhel|ol)
            _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            ;;

        amzn)
            local fullpath=
            fullpath="$(realpath "${dir}")/rhel-7-force${dir_prefix}"
            if test -n "$(shopt -s nullglob; echo "${fullpath}"/*.rpm)" ; then
                _rpm_force_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            else
                _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            fi
            ;;

        *)
            bail "Host package install is not supported on ${LSB_DIST} ${DIST_MAJOR}"
            ;;
    esac
}

function _rpm_force_install_host_packages() {
    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" == "1" ]; then
        logStep "Skipping installation of host packages: ${packages[*]}"
        return
    fi

    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    logStep "Installing host packages ${packages[*]}"

    local fullpath=
    fullpath="$(realpath "${dir}")/rhel-7-force${dir_prefix}"
    if ! test -n "$(shopt -s nullglob; echo "${fullpath}"/*.rpm)" ; then
        echo "Will not install host packages ${packages[*]}, no packages found."
        return 0
    fi

    rpm --upgrade --force --nodeps --nosignature "${fullpath}"/*.rpm

    logSuccess "Host packages ${packages[*]} installed"
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

function _dpkg_apt_get_status_and_maybe_fix_broken_pkgs() {
    logStep "Checking package manager status"
    if apt-get check status ; then
        logSuccess "Status checked successfully. No broken packages were found."
        return
    fi

    logWarn "Attempting to correct broken packages by running sudo apt-get install --fix-broken --yes"
    apt-get install --fix-broken --yes
    if apt-get check status ; then
        logSuccess "Broken packages fixed successfully"
        return
    fi
    bail "Unable to fix broken packages. It is required manual intervention. Run the command '$ apt-get check status' to get further information."
}

function _dpkg_install_host_packages() {
    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" == "1" ]; then
        logStep "Skipping installation of host packages: ${packages[*]}"
        return
    fi

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

    DEBIAN_FRONTEND=noninteractive dpkg --install --force-depends-version --force-confold --auto-deconfigure "${fullpath}"/*.deb

    logSuccess "Host packages ${packages[*]} installed"

    _dpkg_apt_get_status_and_maybe_fix_broken_pkgs
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
    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" == "1" ]; then
        logStep "Skipping installation of host packages: ${packages[*]}"
        return
    fi

    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    logStep "Installing host packages ${packages[*]}"

    local fullpath=
    fullpath="$(_yum_get_host_packages_path "${dir}" "${dir_prefix}")"
    if ! test -n "$(shopt -s nullglob; echo "${fullpath}"/*.rpm)" ; then
        echo "Will not install host packages ${packages[*]}, no packages found."
        return 0
    fi
    cat > /etc/yum.repos.d/kurl.local.repo <<EOF
[kurl.local]
name=kURL Local Repo
baseurl=file://${fullpath}
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF
    # We always use the same repo and we are kinda abusing yum here so we have to clear the cache.
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    yum makecache --disablerepo=* --enablerepo=kurl.local

    # shellcheck disable=SC2086
    if [[ "${packages[*]}" == *"openssl"* && -n $(uname -r | grep "el7") ]]; then
        installed_version=$(yum list available | grep "openssl-libs" | awk '{print $2}' | cut -c 3-)
        # if there is already an openssl-libs package installed, swap with the package version needed for RHEL7
        if [[ -n "${installed_version}" ]]; then
            yum swap openssl-libs-$installed_version openssl-libs-1.0.2k-22.el7_9 -y
        fi
    fi
    # When migrating from Docker to Containerd add-on, Docker is packaged with a higher version of
    # Containerd. We must downgrade Containerd to the version specified as we package the
    # corresponding version of the pause image. If we do not downgrade Containerd, Kubelet will
    # fail to start in airgapped installations with pause image not found.
    if commandExists docker && [ -n "$CONTAINERD_VERSION" ] && [[ "${packages[*]}" == *"containerd.io"* ]]; then
        local next_version=
        local previous_version=
        next_version="$(basename "${fullpath}"/containerd.io*.rpm | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')"
        previous_version="$(ctr -v | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*')"
        logStep "Downgrading containerd, $previous_version -> $next_version"
        if semverCompare "$next_version" "$previous_version" && [ "$SEMVER_COMPARE_RESULT" -lt "0" ]; then
            if uname -r | grep -q "el8" ; then
                yum --disablerepo=* --enablerepo=kurl.local downgrade --allowerasing -y "${packages[@]}"
            else
                yum --disablerepo=* --enablerepo=kurl.local downgrade --allowerasing -y "${packages[@]}"
            fi
        fi
        logSuccess "Downgraded containerd"
    fi
    # shellcheck disable=SC2086
    if [[ "${packages[*]}" == *"containerd.io"* && -n $(uname -r | grep "el8") ]]; then
        yum --disablerepo=* --enablerepo=kurl.local install --allowerasing -y "${packages[@]}"
    else
        yum --disablerepo=* --enablerepo=kurl.local install --allowerasing -y "${packages[@]}"
    fi
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    rm /etc/yum.repos.d/kurl.local.repo

    reset_dnf_module_kurl_local

    logSuccess "Host packages ${packages[*]} installed"
}

function _yum_get_host_packages_path() {
    local dir="$1"
    local dir_prefix="$2"

    local fullpath=
    if [ "${LSB_DIST}" = "ol" ]; then
        if [ "${DIST_VERSION_MAJOR}" = "8" ]; then
            fullpath="$(realpath "${dir}")/ol-8${dir_prefix}"
        else
            fullpath="$(realpath "${dir}")/ol-7${dir_prefix}"
        fi
        if test -n "$(shopt -s nullglob; echo "${fullpath}"/*.rpm)" ; then
            echo "${fullpath}"
            return 0
        fi
    fi

    if [ "${DIST_VERSION_MAJOR}" = "8" ]; then
        echo "$(realpath "${dir}")/rhel-8${dir_prefix}"
    else
        echo "$(realpath "${dir}")/rhel-7${dir_prefix}"
    fi
    return 0
}

# we use a hack and install packages on the host as dnf modules. we need to
# reset the modules after each install as running yum update throws an error
# because it cannot resolve modular dependencies.
function reset_dnf_module_kurl_local() {
    if ! commandExists dnf; then
        return
    fi
    if ! dnf module list | grep -q kurl.local ; then
        return
    fi
    yum module reset -y kurl.local
}
