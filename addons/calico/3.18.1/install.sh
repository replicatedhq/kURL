
CALICO_DISABLE_ENCRYPTION=0 # setting from yaml spec
# Will remain 0 if disabled in the yaml spec and dev workflow in CentOS/RHEL
CALICO_WIREGUARD=0

function calico_pre_init() {
    EXISTING_POD_CIDR=$(kubectl -n kube-system get daemonset calico-node -ojsonpath='{ .spec.template.spec.containers[0].env[?(@.name=="CALICO_IPV4POOL_CIDR")].value}' 2>/dev/null)
}

function calico() {
    local src="$DIR/addons/calico/$CALICO_VERSION"
    local dst="$DIR/kustomize/calico"

    if calico_weave_conflict; then
        printf "${YELLOW}Cannot migrate from weave to calico${NC}\n"
        return 0
    fi

    # can't use kustomize because the CRDs must be applied first
    cp "$src/calico.yaml" "$dst/"
    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/ip-in-ip-encapsulation.yaml" "$dst/"
    render_yaml_file "$src/tmpl-daemonset-pod-cidr.yaml" > "$dst/daemonset-pod-cidr.yaml"
    kubectl apply -k "$dst/"

    calico_cli
    calico_wireguard

    echo "Waiting for default FelixConfiguration to configure encryption"
    if ! spinner_until 180 kubernetes_cluster_resource_exists felixconfiguration default; then
        bail "Failed to find default FelixConfiguration resource"
    fi
    if [ "$CALICO_WIREGUARD" = "1" ]; then
        calicoctl patch felixconfiguration default --type='merge' -p '{"spec":{"wireguardEnabled":true}}'
    else
        calicoctl patch felixconfiguration default --type='merge' -p '{"spec":{"wireguardEnabled":false}}'
    fi
}

function calico_join() {
    if calico_weave_conflict; then
        printf "${YELLOW}Cannot migrate from weave to calico${NC}\n"
        return 0
    fi

    calico_cli
    calico_wireguard
}

function calico_cli() {
    local src="$DIR/addons/calico/$CALICO_VERSION"

    if [ ! -f "$src/assets/calicoctl" ] && [ ! "$AIRGAP" = "1" ]; then
        mkdir -p "$src/assets"
        curl -L https://github.com/projectcalico/calicoctl/releases/download/v${CALICO_VERSION}/calicoctl > "$src/assets/calicoctl"
    fi

    chmod +x "$src/assets/calicoctl"
    mv "$src/assets/calicoctl" /usr/local/bin/
}

function calico_wireguard() {
    local src="$DIR/addons/calico/$CALICO_VERSION"

    if [ "$CALICO_DISABLE_WIREGUARD" ]; then
        return 0
    fi

    if modprobe wireguard; then
        echo "Wireguard already installed"
        CALICO_WIREGUARD=1
        return 0
    fi

    if [ -d $src/*/archives ]; then
        install_host_archives "$src"
        CALICO_WIREGUARD=1
        return 0
    fi

    # For dev workflows with rsync
    if [ "$AIRGAP" != "1" ] && [ "$LSB_DIST" = "ubuntu" ]; then
        apt update -y && apt install -y wireguard
        CALICO_WIREGUARD=1
        return 0
    fi

    # dev on CentOS/RHEL with rsync
    printf "${YELLOW}Wireguard not installed. Encryption disabled.\n${NC}"
}

function calico_weave_conflict() {
    if [ -f /etc/cni/net.d/10-weave.conflist ]; then
        return 0
    fi
    return 1
}
