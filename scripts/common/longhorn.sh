function longhorn_host_init() {
    longhorn_install_iscsi_if_missing $1
    longhorn_install_nfs_utils_if_missing $1
    mkdir -p /var/lib/longhorn
    chmod 700 /var/lib/longhorn
}

function longhorn_install_iscsi_if_missing() {
    local src=$1

    if ! systemctl list-units | grep -q iscsid ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" open-iscsi
                ;;

            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" iscsi-initiator-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active iscsid; then
        systemctl start iscsid
    fi

    if ! systemctl -q is-enabled iscsid; then
        systemctl enable iscsid
    fi
}

function longhorn_install_nfs_utils_if_missing() {
    local src=$1

    if ! systemctl list-units | grep -q nfs-utils ; then
        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" nfs-common
                ;;

            centos|rhel|amzn|ol)
                yum_install_host_archives "$src" nfs-utils
                ;;
        esac
    fi

    if ! systemctl -q is-active nfs-utils; then
        systemctl start nfs-utils
    fi

    if ! systemctl -q is-enabled nfs-utils; then
        systemctl enable nfs-utils
    fi
}
