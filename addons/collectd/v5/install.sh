function collectd() {
    local src="$DIR/addons/collectd/$COLLECTD_VERSION"
    
    if ! systemctl list-units | grep -q collectd; then
        # collectd config needs to be created before service starts for the first time.
        # otherwise over 100MB of extra rrd files will be created.
        collectd_ensure_hostname_resolves
        collectd_config $src

        case "$LSB_DIST" in
            ubuntu)
                dpkg_install_host_archives "$src" collectd
                ;;

            centos|rhel|ol|rocky|amzn)
                if [ "$DIST_VERSION_MAJOR" = "8" ] || [ "$DIST_VERSION_MAJOR" = "9" ]; then
                    yum_install_host_archives "$src" collectd collectd-rrdtool collectd-disk
                else
                    yum_install_host_archives "$src" collectd collectd-rrdtool
                fi
                ;;
        esac

        systemctl restart collectd
        collectd_service_enable
    else
        printf "${YELLOW} Collectd is running, skipping installation${NC}\n"
    fi
}

function collectd_service_enable() {
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
    centos|rhel|ol|rocky|amzn)
        local conf_path="/etc"
        mkdir -p /var/lib/collectd/rrd > /dev/null 2>&1
        ;;
    esac

    mkdir -p $conf_path
    if [ -f "$conf_path/collectd.conf" ]; then
        cp -f "$conf_path/collectd.conf" "$conf_path/collectd.old.$(date +%s)"
    fi

    cp -f "$src/collectd.conf" "$conf_path/collectd.conf"
}

function collectd_join() {
    collectd
}

function collectd_ensure_hostname_resolves() {
    local host="$(get_local_node_name)"

    set +e
    curl -s --max-time 1 http://${host} > /dev/null
    local status=$?
    set -e

    if [ "$status" = "6" ]; then
        printf "${YELLOW}Cannot resolve ${host}. The following line will be added to /etc/hosts:\n\n"
        printf "\t${PRIVATE_ADDRESS}\t${host}${NC}\n\nAllow? "
        if ! confirmY; then
            bail "Collectd must be able to resolve ${host}"
        fi
        echo "${PRIVATE_ADDRESS}    ${host}" >> /etc/hosts
    fi
}
