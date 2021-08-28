
function antrea_pre_init() {
    local src="$DIR/addons/antrea/$ANTREA_VERSION"

    POD_CIDR="$ANTREA_POD_CIDR"
    POD_CIDR_RANGE="$ANTREA_POD_CIDR_RANGE"

    cp "$src/kubeadm.yaml" "$DIR/kustomize/kubeadm/init-patches/antrea.yaml"

    if commandExists kubectl; then
        EXISTING_POD_CIDR=$(kubectl -n kube-system get cm kubeadm-config -oyaml 2>/dev/null | grep podSubnet | awk '{ print $NF }')
    fi
}

function antrea() {
    local src="$DIR/addons/antrea/$ANTREA_VERSION"
    local dst="$DIR/kustomize/antrea"

    if antrea_weave_conflict; then
        printf "${YELLOW}Cannot migrate from weave to antrea${NC}\n"
        return 0
    fi

    if ! lsmod | grep ip_tables; then
        modprobe ip_tables
    fi

    cp "$src/kustomization.yaml" "$dst/"

    if [ "$ANTREA_DISABLE_ENCRYPTION" = "1" ]; then
        cp "$src/plaintext.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" plaintext.yaml
    else
        cp "$src/ipsec.yaml" "$dst/"
        insert_resources "$dst/kustomization.yaml" ipsec.yaml

        ANTREA_IPSEC_PSK=$(kubernetes_secret_value kube-system antrea-ipsec psk)
        if [ -z "$ANTREA_IPSEC_PSK" ]; then
            ANTREA_IPSEC_PSK=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
        fi
        render_yaml_file "$src/ipsec-psk.yaml" > "$dst/ipsec-psk.yaml"
        insert_patches_strategic_merge "$dst/kustomization.yaml" ipsec-psk.yaml
    fi

    kubectl apply -k $dst

    antrea_cli

    check_network
}

function antrea_join() {
    if ! lsmod | grep ip_tables; then
        modprobe ip_tables
    fi

    if kubernetes_is_master; then
        antrea_cli
    fi
}

function antrea_cli() {
  local src="$DIR/addons/antrea/$ANTREA_VERSION"
    
  if [ ! -f "$src/assets/antctl" ] && [ "$AIRGAP" != "1" ]; then
    mkdir -p "$src/assets"
    curl -L --fail "https://github.com/vmware-tanzu/antrea/releases/download/v${ANTREA_VERSION}/antctl-Linux-x86_64" > "$src/assets/antctl"
  fi

  chmod +x "$src/assets/antctl"
  # put it in the same directory as kubectl since that's always on the path
  cp "$src/assets/antctl" "$(dirname $(which kubectl))/"
}

function antrea_weave_conflict() {
    if [ -f /etc/cni/net.d/10-weave.conflist ]; then
        return 0
    fi
    return 1
}
