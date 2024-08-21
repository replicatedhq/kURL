#!/bin/bash

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

        centos|rhel|ol|rocky)
            if [ "$DIST_VERSION_MAJOR" = "9" ]; then
                _yum_install_host_packages_el9 "$dir" "$dir_prefix" "${packages[@]}"
            else
                _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
            fi
            ;;

        amzn)
            if is_amazon_2023; then
                _yum_install_host_packages_el9 "$dir" "$dir_prefix" "${packages[@]}"
            else
                local fullpath=
                fullpath="$(realpath "${dir}")/rhel-7-force${dir_prefix}"
                if test -n "$(shopt -s nullglob; echo "${fullpath}"/*.rpm)" ; then
                    _rpm_force_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
                else
                    _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
                fi
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

    logWarn "Attempting to correct broken packages by running 'apt-get install --fix-broken --no-remove --yes'"
    # Let's use || true here for when be required to remove the packages we properly should the error message
    # with the steps to get it fix manually
    apt-get install --fix-broken --no-remove --yes || true
    if apt-get check status ; then
        logSuccess "Broken packages fixed successfully"
        return
    fi
    logFail "Unable to fix broken packages. Manual intervention is required."
    logFail "Run the command 'apt-get check status' to get further information."
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
    if [ "$DIST_VERSION_MAJOR" = "9" ] || [ "$DIST_VERSION_MAJOR" = "2023" ]; then
        _yum_install_host_packages_el9 "$dir" "$dir_prefix" "${packages[@]}"
    else
        _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
    fi
}

function yum_install_host_packages() {
    local dir="$1"
    local dir_prefix=""
    local packages=("${@:2}")
    if [ "$DIST_VERSION_MAJOR" = "9" ] || [ "$DIST_VERSION_MAJOR" = "2023" ]; then
        _yum_install_host_packages_el9 "$dir" "$dir_prefix" "${packages[@]}"
    else
        _yum_install_host_packages "$dir" "$dir_prefix" "${packages[@]}"
    fi
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
                yum --disablerepo=* --enablerepo=kurl.local downgrade -y "${packages[@]}"
            fi
        fi
        logSuccess "Downgraded containerd"
    fi
    # shellcheck disable=SC2086
    if [[ "${packages[*]}" == *"containerd.io"* && -n $(uname -r | grep "el8") ]]; then
        yum --disablerepo=* --enablerepo=kurl.local install --allowerasing -y "${packages[@]}"
    else
        yum --disablerepo=* --enablerepo=kurl.local install -y "${packages[@]}"
    fi
    yum clean metadata --disablerepo=* --enablerepo=kurl.local
    rm /etc/yum.repos.d/kurl.local.repo

    reset_dnf_module_kurl_local

    logSuccess "Host packages ${packages[*]} installed"
}

function _yum_install_host_packages_el9() {
    if [ "${SKIP_SYSTEM_PACKAGE_INSTALL}" == "1" ]; then
        logStep "Skipping installation of host packages: ${packages[*]}"
        return
    fi

    local dir="$1"
    local dir_prefix="$2"
    local packages=("${@:3}")

    logStep "Installing host packages ${packages[*]}"

    local fullpath=
    fullpath="$(_yum_get_host_packages_path "$dir" "$dir_prefix")"
    if ! test -n "$(shopt -s nullglob; echo "$fullpath"/*.rpm)" ; then
        echo "Will not install host packages ${packages[*]}, no packages found."
        return 0
    fi

    local repoprefix=
    repoprefix="$(echo "${dir%"/"}" | awk -F'/' '{ print $(NF-1) "-" $NF }')"
    if [ -n "$dir_prefix" ]; then
        repoprefix="$repoprefix.${dir_prefix/#"/"}"
    fi

    local reponame="$repoprefix.kurl.local"
    local repopath="$KURL_INSTALL_DIRECTORY.repos/$repoprefix"

    mkdir -p "$KURL_INSTALL_DIRECTORY.repos"
    rm -rf "$repopath"
    cp -r "$fullpath" "$repopath"

    cat > "/etc/yum.repos.d/$reponame.repo" <<EOF
[$reponame]
name=kURL $repoprefix Local Repo
baseurl=file://$repopath
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

    if [[ "${packages[*]}" == *"containerd.io"* ]] ; then
        yum install --disableplugin amazon-id,subscription-manager --repo="$reponame" --allowerasing -y "${packages[@]}"
    else
        yum install --disableplugin amazon-id,subscription-manager --repo="$reponame" -y "${packages[@]}"
    fi

    logSuccess "Host packages ${packages[*]} installed"
}

function _yum_get_host_packages_path() {
    local dir="$1"
    local dir_prefix="$2"

    local fullpath=
    if [ "${LSB_DIST}" = "ol" ]; then
        if [ "$DIST_VERSION_MAJOR" = "9" ]; then
            fullpath="$(realpath "${dir}")/ol-9${dir_prefix}"
        elif [ "$DIST_VERSION_MAJOR" = "8" ]; then
            fullpath="$(realpath "${dir}")/ol-8${dir_prefix}"
        else
            fullpath="$(realpath "${dir}")/ol-7${dir_prefix}"
        fi
        if test -n "$(shopt -s nullglob; echo "${fullpath}"/*.rpm)" ; then
            echo "${fullpath}"
            return 0
        fi
    fi

    if [ "$DIST_VERSION_MAJOR" = "9" ]; then
        echo "$(realpath "${dir}")/rhel-9${dir_prefix}"
    elif [ "$DIST_VERSION_MAJOR" = "2023" ]; then
        echo "$(realpath "${dir}")/amazon-2023${dir_prefix}"
    elif [ "$DIST_VERSION_MAJOR" = "8" ]; then
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
    yum module reset -y kurl.local 2>/dev/null || true
}

# host_packages_shipped returns true if we do ship host packages for the distro
# we are running the installation on.
function host_packages_shipped() {
    if ! is_rhel_9_variant && ! is_amazon_2023 && ! is_ubuntu_2404; then
        return 0
    fi
    return 1
}

# is_rhel_9_variant returns 0 if the current distro is RHEL 9 or a derivative
function is_rhel_9_variant() {
    if [ "$DIST_VERSION_MAJOR" != "9" ]; then
        return 1
    fi

    case "$LSB_DIST" in
        centos|rhel|ol|rocky)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# is_amazon_2023 returns 0 if the current distro is Amazon 2023.
function is_amazon_2023() {
    if [ "$DIST_VERSION_MAJOR" != "2023" ]; then
        return 1
    fi
    if [ "$LSB_DIST" != "amzn" ]; then
        return 1
    fi
    return 0
}

# is_ubuntu_2404 returns 0 if the current distro is Ubuntu 24.04.
function is_ubuntu_2404() {
    if [ "$DIST_VERSION_MAJOR" != "24.04" ]; then
        return 1
    fi
    if [ "$LSB_DIST" != "ubuntu" ]; then
        return 1
    fi
    return 0
}

# ensure_host_package calls either _apt_ensure_host_package or _yum_ensure_host_package
function ensure_host_package() {
    local yum_package="$1"
    local apt_package="$1"

    case "$LSB_DIST" in
        ubuntu)
            if [ -n "$apt_package" ] && [ "$apt_package" != "skip" ]; then
                _apt_ensure_host_package "$apt_package"
            fi
            ;;

        centos|rhel|ol|rocky|amzn)
            if [ -n "$yum_package" ] && [ "$yum_package" != "skip" ]; then
                _yum_ensure_host_package "$yum_package"
            fi
            ;;

        *)
            bail "Host package checks are not supported on ${LSB_DIST} ${DIST_MAJOR}"
            ;;
    esac
}

# _apt_ensure_host_package ensures that a package is installed on the host
function _apt_ensure_host_package() {
    local package="$1"

    if ! apt_is_host_package_installed "$package" ; then
        logStep "Installing host package $package"
        if ! apt install -y "$package" ; then
            logFail "Failed to install host package $package."
            logFail "Please install $package and try again."
            bail "    apt install $package"
        fi
        logSuccess "Host package $package installed"
    fi
}

# _yum_ensure_host_package ensures that a package is installed on the host
function _yum_ensure_host_package() {
    local package="$1"

    if ! yum_is_host_package_installed "$package" ; then
        logStep "Installing host package $package"
        if ! yum install -y "$package" ; then
            logFail "Failed to install host package $package."
            logFail "Please install $package and try again."
            bail "    yum install $package"
        fi
        logSuccess "Host package $package installed"
    fi
}

# preflights_require_host_packages ensures that all required host packages are installed.
function preflights_require_host_packages() {
    if host_packages_shipped ; then
        return
    fi

    logStep "Checking required host packages"

    local seen=()
    local fail=0
    local skip=0
    # shellcheck disable=SC2044
    for deps_file in $(find . -name Deps); do
        while read -r dep ; do

            skip=0
            for seen_item in "${seen[@]}"; do
                if [ "$dep" = "$seen_item" ]; then
                    skip=1
                    break
                fi
            done
            if [ "$skip" = "1" ]; then
                continue
            fi
            seen+=("$dep")

            if ! echo "$deps_file" | grep -q "rhel-9"; then
                if ! echo "$deps_file" | grep -q "amazon-2023"; then
                    if ! echo "$deps_file" | grep -q "ubuntu-24.04"; then
                        continue
                    fi
                fi
            fi
            if rpm -q "$dep" >/dev/null 2>&1 ; then
                continue
            fi
            fail=1
            component=$(echo "$deps_file" | awk -F'/' '{print $3}')
            if [ "$component" = "host" ]; then
                logFail "Host package $dep is required"
                continue
            fi
            version=$(echo "$deps_file" | awk -F'/' '{print $4}')
            logFail "Host package $dep is required for $component version $version"
        done <"$deps_file"
    done

    if [ "$fail" = "1" ]; then
        echo ""
        log "Host packages are missing. Please install them and re-run the install script."
        exit 1
    fi
    logSuccess "Required host packages are installed or available"
}

# apt_is_host_package_installed returns 0 if the package is installed on the host
function apt_is_host_package_installed() {
    local package="$1"

    log "Checking if $package is installed"
    apt list --installed "$package" >/dev/null 2>&1
}

# yum_is_host_package_installed returns 0 if the package is installed on the host
function yum_is_host_package_installed() {
    local package="$1"

    log "Checking if $package is installed"
    yum list installed "$package" >/dev/null 2>&1
}
