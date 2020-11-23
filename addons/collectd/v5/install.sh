function collectd() {
    local src="$DIR/addons/collectd/$COLLECTD_VERSION"
    
    if ! systemctl list-units | grep -q collectd; then
        printf "${YELLOW}Installing collectd${NC}\n"

        # collectd config needs to be created before service starts for the first time.
        # otherwise over 100MB of extra rrd files will be created.
        collectd_ensure_hostname_resolves
        collectd_config $src

        case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version -o Dpkg::Options::="--force-confold" ${src}/ubuntu-${DIST_VERSION}/archives/*.deb
            ;;
        centos|rhel)
            rpm --upgrade --force --nodeps ${src}/rhel-${DIST_VERSION_MAJOR}/archives/*.rpm
            ;;
        amzn)
            rpm --upgrade --force --nodeps ${src}/rhel-7/archives/*.rpm
            ;;
        *)
            printf"${YELLOW}Unsupported OS for collectd installation${NC}\n"
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
    centos|rhel|amzn)
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
    local host=$(hostname)

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
