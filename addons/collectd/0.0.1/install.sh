function collectd() {
    local src="$DIR/addons/collectd/$COLLECTD_VERSION"
    
    if ! systemctl list-units | grep -q collectd; then
        printf "${YELLOW}Installing collectd\n"
        case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version ${src}/ubuntu-${DIST_VERSION}/archives/*.deb
            ;;
        centos|rhel|amzn)
            rpm --upgrade --force --nodeps ${src}/rhel-${DIST_VERSION}/archives/*.rpm
            ;;
        *)
            printf"${YELLOW}Unsupported OS for collectd installation\n"
            ;;
        esac

        collectd_config $src
        collectd_service
    else
        printf "${YELLOW} Collectd is running, skipping installation\n"
    fi
}

function collectd_service() {
    if ! systemctl -q is-active collectd; then
        systemctl start collectd
    fi

    if ! systemctl -q is-enabled collectd; then
        systemctl enable collectd
    fi
}

function collectd_config() {
    local src="$1"

    case "$LSB_DIST" in
    ubuntu)
        local conf_path="/etc/collectd"
        ;;
    centos|rhel|amzn)
        local conf_path="/etc"
        mkdir -p /var/lib/collectd/rrd > /dev/null 2>&1
        ;;
    esac

    if [ -f "$conf_path/collectd.conf" ]; then
        cp -fn "$conf_path/collectd.conf" "$conf_path/collectd.old"
    fi

    cp -fn "$src/collectd.conf" "$conf_path/collectd.conf"
    systemctl restart collectd
}

function collectd_join() {
    collectd
}
