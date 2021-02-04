# Gather any additional information required from the user that could not be discovered and was not
# passed with a flag

function prompts() {
    if [ -z "$PRIVATE_ADDRESS" ]; then
        promptForPrivateIp
    fi
    # TODO public address? only required for adding SAN to K8s API server cert

    prompt_airgap_preload_images

    if [ "$HA_CLUSTER" = "1" ]; then
        promptForLoadBalancerAddress
    fi
}

if [ -z "$READ_TIMEOUT" ]; then
    READ_TIMEOUT="-t 20"
fi

promptTimeout() {
    set +e
    if [ -z "$FAST_TIMEOUTS" ]; then
        read ${1:-$READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    else
        read ${READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    fi
    set -e
}

confirmY() {
    printf "(Y/n) "
    if [ "$ASSUME_YES" = "1" ]; then
        echo "Y"
        return 0
    fi
    promptTimeout "$@"
    if [ "$PROMPT_RESULT" = "n" ] || [ "$PROMPT_RESULT" = "N" ]; then
        return 1
    fi
    return 0
}

confirmN() {
    printf "(y/N) "
    if [ "$ASSUME_YES" = "1" ]; then
        echo "Y"
        return 0
    fi
    promptTimeout "$@"
    if [ "$PROMPT_RESULT" = "y" ] || [ "$PROMPT_RESULT" = "Y" ]; then
        return 0
    fi
    return 1
}

# even if someone has set ASSUME_YES, we shouldn't automatically upload a support bundle
supportBundleConfirmN() {
    printf "(y/N) "
    if [ "$ASSUME_YES" = "1" ]; then
        echo "N"
        return 1
    fi
    promptTimeout "$@"
    if [ "$PROMPT_RESULT" = "y" ] || [ "$PROMPT_RESULT" = "Y" ]; then
        return 0
    fi
    return 1
}

prompt() {
    if [ "$ASSUME_YES" = "1" ]; then
        return 0
    fi
    set +e
    read PROMPT_RESULT < /dev/tty
    set -e
}

function joinPrompts() {
    if [ -n "$API_SERVICE_ADDRESS" ]; then
        splitHostPort "$API_SERVICE_ADDRESS"
        if [ -z "$PORT" ]; then
            PORT="6443"
        fi
        KUBERNETES_MASTER_ADDR="$HOST"
        KUBERNETES_MASTER_PORT="$PORT"
        LOAD_BALANCER_ADDRESS="$HOST"
        LOAD_BALANCER_PORT="$PORT"
    else
        promptForMasterAddress
        splitHostPort "$KUBERNETES_MASTER_ADDR"
        if [ -n "$PORT" ]; then
            KUBERNETES_MASTER_ADDR="$HOST"
            KUBERNETES_MASTER_PORT="$PORT"
        else
            KUBERNETES_MASTER_PORT="6443"
        fi 
        LOAD_BALANCER_ADDRESS="$KUBERNETES_MASTER_ADDR"
        LOAD_BALANCER_PORT="$KUBERNETES_MASTER_PORT"
        API_SERVICE_ADDRESS="${KUBERNETES_MASTER_ADDR}:${KUBERNETES_MASTER_PORT}"
    fi
    promptForToken
    promptForTokenCAHash
}

promptForToken() {
    if [ -n "$KUBEADM_TOKEN" ]; then
        return
    fi

    printf "Please enter the kubernetes discovery token.\n"
    while true; do
        printf "Kubernetes join token: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN="$PROMPT_RESULT"
            return
        fi
    done
}

promptForTokenCAHash() {
    if [ -n "$KUBEADM_TOKEN_CA_HASH" ]; then
        return
    fi

    printf "Please enter the discovery token CA's hash.\n"
    while true; do
        printf "Kubernetes discovery token CA hash: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBEADM_TOKEN_CA_HASH="$PROMPT_RESULT"
            return
        fi
    done
}

promptForMasterAddress() {
    if [ -n "$KUBERNETES_MASTER_ADDR" ]; then
        return
    fi

    printf "Please enter the Kubernetes master address.\n"
    printf "e.g. 10.128.0.4\n"
    while true; do
        printf "Kubernetes master address: "
        prompt
        if [ -n "$PROMPT_RESULT" ]; then
            KUBERNETES_MASTER_ADDR="$PROMPT_RESULT"
            return
        fi
    done
}

promptForLoadBalancerAddress() {
    local lastLoadBalancerAddress=

    if kubeadm config view >/dev/null 2>&1; then
        lastLoadBalancerAddress="$(kubeadm config view | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g')"
        if [ -n "$lastLoadBalancerAddress" ]; then
            splitHostPort "$lastLoadBalancerAddress"
            if [ "$HOST" = "$lastLoadBalancerAddress" ]; then
                lastLoadBalancerAddress="$lastLoadBalancerAddress:6443"
            fi
        fi
    fi

    if [ -n "$LOAD_BALANCER_ADDRESS" ] && [ -n "$lastLoadBalancerAddress" ]; then
        splitHostPort "$LOAD_BALANCER_ADDRESS"
        if [ "$HOST" = "$LOAD_BALANCER_ADDRESS" ]; then
            LOAD_BALANCER_ADDRESS="$LOAD_BALANCER_ADDRESS:6443"
        fi
        if [ "$LOAD_BALANCER_ADDRESS" != "$lastLoadBalancerAddress" ]; then
            LOAD_BALANCER_ADDRESS_CHANGED=1
        fi
    fi

    if [ -z "$LOAD_BALANCER_ADDRESS" ] && [ -n "$lastLoadBalancerAddress" ]; then
        LOAD_BALANCER_ADDRESS="$lastLoadBalancerAddress"
    fi

    if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
        printf "Please enter a load balancer address to route external and internal traffic to the API servers.\n"
        printf "In the absence of a load balancer address, all traffic will be routed to the first master.\n"
        printf "Load balancer address: "
        prompt
        LOAD_BALANCER_ADDRESS="$PROMPT_RESULT"
        if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
            LOAD_BALANCER_ADDRESS="$PRIVATE_ADDRESS"
            LOAD_BALANCER_PORT=6443
        fi
    fi

    if [ -z "$LOAD_BALANCER_PORT" ]; then
        splitHostPort "$LOAD_BALANCER_ADDRESS"
        LOAD_BALANCER_ADDRESS="$HOST"
        LOAD_BALANCER_PORT="$PORT"
    fi
    if [ -z "$LOAD_BALANCER_PORT" ]; then
        LOAD_BALANCER_PORT=6443
    fi
}

# if remote nodes are in the cluster and this is an airgap install, prompt the user to run the
# load-images task on all remotes before proceeding because remaining steps may cause pods to
# be scheduled on those nodes with new images.
function prompt_airgap_preload_images() {
    if [ "$AIRGAP" != "1" ]; then
        return 0
    fi

    if ! kubernetes_has_remotes; then
        return 0
    fi
 
    while read -r node; do
        local nodeName=$(echo "$node" | awk '{ print $1 }')
        if [ "$nodeName" = "$(hostname)" ]; then
            continue
        fi
        if kubernetes_node_has_all_images "$nodeName"; then
            continue
        fi
        local kurl_install_directory_flag="$(get_kurl_install_directory_flag "${KURL_INSTALL_DIRECTORY_FLAG}")"
        printf "\nRun this script on node ${GREEN}${nodeName}${NC} to load required images before proceeding:\n"
        printf "\n"
        printf "${GREEN}\tcat ./tasks.sh | sudo bash -s load-images${kurl_install_directory_flag}${NC}"
        printf "\n"

        while true; do
            echo ""
            printf "Have images been loaded on node ${nodeName}? "
            if confirmY " "; then
                break
            fi
        done
    done < <(kubectl get nodes --no-headers)
}

promptForPublicIp() {
    if [ -n "$PUBLIC_ADDRESS" ]; then
        return 0;
    fi

    while true; do
        printf "Public IP address: "
        promptTimeout "-t 120"
        if [ -n "$PROMPT_RESULT" ]; then
            if isValidIpv4 "$PROMPT_RESULT"; then
                PUBLIC_ADDRESS=$PROMPT_RESULT
                break
            else
                printf "%s is not a valid ip address.\n" "$PROMPT_RESULT"
            fi
        else
            break
        fi
    done
}

promptForPrivateIp() {
    _count=0
    _regex="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+[[:alnum:]]+ ([[:digit:].]+)"
    while read -r _line; do
        [[ $_line =~ $_regex ]]
        if [ "${BASH_REMATCH[1]}" != "lo" ] && [ "${BASH_REMATCH[1]}" != "kube-ipvs0" ] && [ "${BASH_REMATCH[1]}" != "docker0" ] && [ "${BASH_REMATCH[1]}" != "weave" ]; then
            _iface_names[$((_count))]=${BASH_REMATCH[1]}
            _iface_addrs[$((_count))]=${BASH_REMATCH[2]}
            let "_count += 1"
        fi
    done <<< "$(ip -4 -o addr)"
    if [ "$_count" -eq "0" ]; then
        echo >&2 "Error: The installer couldn't discover any valid network interfaces on this machine."
        echo >&2 "Check your network configuration and re-run this script again."
        echo >&2 "If you want to skip this discovery process, pass the 'local-address' arg to this script, e.g. 'sudo ./install.sh local-address=1.2.3.4'"
        exit 1
    elif [ "$_count" -eq "1" ]; then
        PRIVATE_ADDRESS=${_iface_addrs[0]}
        printf "The installer will use network interface '%s' (with IP address '%s')\n" "${_iface_names[0]}" "${_iface_addrs[0]}"
        return
    fi
    printf "The installer was unable to automatically detect the private IP address of this machine.\n"
    printf "Please choose one of the following network interfaces:\n"
    for i in $(seq 0 $((_count-1))); do
        printf "[%d] %-5s\t%s\n" "$i" "${_iface_names[$i]}" "${_iface_addrs[$i]}"
    done
    while true; do
        printf "Enter desired number (0-%d): " "$((_count-1))"
        prompt
        if [ -z "$PROMPT_RESULT" ]; then
            continue
        fi
        if [ "$PROMPT_RESULT" -ge "0" ] && [ "$PROMPT_RESULT" -lt "$_count" ]; then
            PRIVATE_ADDRESS=${_iface_addrs[$PROMPT_RESULT]}
            printf "The installer will use network interface '%s' (with IP address '%s').\n" "${_iface_names[$PROMPT_RESULT]}" "$PRIVATE_ADDRESS"
            return
        fi
    done
}
