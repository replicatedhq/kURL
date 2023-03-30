# shellcheck disable=SC2148
# Gather any additional information required from the user that could not be discovered and was not
# passed with a flag

function prompts_can_prompt() {
    # Need the TTY to accept input and stdout to display
    # Prompts when running the script through the terminal but not as a subshell
    if [ -c /dev/tty ]; then
        return 0
    fi
    return 1
}

function prompt() {
    if ! prompts_can_prompt ; then
        bail "Cannot prompt, shell is not interactive"
    fi

    set +e
    if [ -z ${TEST_PROMPT_RESULT+x} ]; then
        read PROMPT_RESULT < /dev/tty
    else
        PROMPT_RESULT="$TEST_PROMPT_RESULT"
    fi
    set -e
}

function confirmY() {
    printf "(Y/n) "
    if [ "$ASSUME_YES" = "1" ]; then
        echo "Y"
        return 0
    fi
    if ! prompts_can_prompt ; then
        echo "Y"
        logWarn "Automatically accepting prompt, shell is not interactive"
        return 0
    fi
    prompt
    if [ "$PROMPT_RESULT" = "n" ] || [ "$PROMPT_RESULT" = "N" ]; then
        return 1
    fi
    return 0
}

function confirmN() {
    printf "(y/N) "
    if [ "$ASSUME_YES" = "1" ]; then
        echo "Y"
        return 0
    fi
    if ! prompts_can_prompt ; then
        echo "N"
        logWarn "Automatically declining prompt, shell is not interactive"
        return 1
    fi
    prompt
    if [ "$PROMPT_RESULT" = "y" ] || [ "$PROMPT_RESULT" = "Y" ]; then
        return 0
    fi
    return 1
}

function join_prompts() {
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
        prompt_for_master_address
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
    prompt_for_token
    prompt_for_token_ca_hash
}

function prompt_for_token() {
    if [ -n "$KUBEADM_TOKEN" ]; then
        return
    fi
    if ! prompts_can_prompt ; then
        bail "kubernetes.kubeadmToken required"
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

function prompt_for_token_ca_hash() {
    if [ -n "$KUBEADM_TOKEN_CA_HASH" ]; then
        return
    fi
    if ! prompts_can_prompt ; then
        bail "kubernetes.kubeadmTokenCAHash required"
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

function prompt_for_master_address() {
    if [ -n "$KUBERNETES_MASTER_ADDR" ]; then
        return
    fi
    if ! prompts_can_prompt ; then
        bail "kubernetes.masterAddress required"
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

function common_prompts() {
    if [ -z "$PRIVATE_ADDRESS" ]; then
        prompt_for_private_ip
    fi
    # TODO public address? only required for adding SAN to K8s API server cert

    prompt_airgap_preload_images

    if [ "$HA_CLUSTER" = "1" ]; then
        prompt_for_load_balancer_address
    fi
}

function prompt_license() {
    if [ -n "$LICENSE_URL" ]; then
        if [ "$AIRGAP" = "1" ]; then
            bail "License Agreements with Airgap installs are not supported yet.\n"
            return
        fi
        curl --fail $LICENSE_URL || bail "Failed to fetch license at url: $LICENSE_URL"
        printf "\n\nThe license text is reproduced above. To view the license in your browser visit $LICENSE_URL.\n\n"
        printf "Do you accept the license agreement?"
        if confirmN; then
            printf "License Agreement Accepted. Continuing Installation.\n"
        else
            bail "License Agreement Not Accepted. 'y' or 'Y' needed to accept. Exiting installation."
        fi
    fi
}

function prompt_for_load_balancer_address() {
    local lastLoadBalancerAddress=

    if kubeadm_cluster_configuration >/dev/null 2>&1; then
        lastLoadBalancerAddress="$(kubeadm_cluster_configuration | grep 'controlPlaneEndpoint:' | sed 's/controlPlaneEndpoint: \|"//g')"
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

    if [ -z "$LOAD_BALANCER_ADDRESS" ] && [ "$KUBERNETES_LOAD_BALANCER_USE_FIRST_PRIMARY" = "1" ]; then
        # EKCO_ENABLE_INTERNAL_LOAD_BALANCER takes precedence
        if [ -z "$EKCO_VERSION" ] || [ "$EKCO_ENABLE_INTERNAL_LOAD_BALANCER" != "1" ]; then
            LOAD_BALANCER_ADDRESS="$PRIVATE_ADDRESS"
            LOAD_BALANCER_PORT=6443
        fi
    fi

    if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
        if ! prompts_can_prompt ; then
            bail "kubernetes.loadBalancerAddress required"
        fi

        if [ -n "$EKCO_VERSION" ] && semverCompare "$EKCO_VERSION" "0.11.0" && [ "$SEMVER_COMPARE_RESULT" -ge "0" ]; then
            printf "\nIf you would like to bring your own load balancer to route external and internal traffic to the API servers, please enter a load balancer address.\n"
            printf "HAProxy will be used to perform this load balancing internally if you do not provide a load balancer address.\n"
            printf "Load balancer address: "
            prompt
            LOAD_BALANCER_ADDRESS="$PROMPT_RESULT"
            if [ -z "$LOAD_BALANCER_ADDRESS" ]; then
                EKCO_ENABLE_INTERNAL_LOAD_BALANCER=1
            fi
        else
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
    fi

    if [ -z "$LOAD_BALANCER_PORT" ]; then
        splitHostPort "$LOAD_BALANCER_ADDRESS"
        LOAD_BALANCER_ADDRESS="$HOST"
        LOAD_BALANCER_PORT="$PORT"
    fi
    if [ -z "$LOAD_BALANCER_PORT" ]; then
        LOAD_BALANCER_PORT=6443
    fi

    # localhost:6444 is the address of the internal load balancer
    if [ "$LOAD_BALANCER_ADDRESS" = "localhost" ] && [ "$LOAD_BALANCER_PORT" = "6444" ]; then
        EKCO_ENABLE_INTERNAL_LOAD_BALANCER=1
    fi

    if [ -n "$LOAD_BALANCER_ADDRESS" ]; then
        $BIN_BASHTOYAML -c "$MERGED_YAML_SPEC" -f "load-balancer-address=${LOAD_BALANCER_ADDRESS}:${LOAD_BALANCER_PORT}"
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

    local unattended_nodes_missing_images=0

    while read -r node; do
        local nodeName=$(echo "$node" | awk '{ print $1 }')
        if [ "$nodeName" = "$(get_local_node_name)" ]; then
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

        if [ "${KURL_IGNORE_REMOTE_LOAD_IMAGES_PROMPT}" != "1" ]; then
            if ! prompts_can_prompt ; then
                unattended_nodes_missing_images=1
                continue
            fi

            while true; do
                echo ""
                printf "Have images been loaded on node ${nodeName}? "
                if confirmN ; then
                    break
                fi
            done
        else
            logWarn "Remote load-images task prompt explicitly ignored"
        fi
    done < <(kubectl get nodes --no-headers)

    if [ "$unattended_nodes_missing_images" = "1" ] ; then
        bail "Preloading images required"
    fi
}

function prompt_for_private_ip() {
    _count=0

    if [ "$IPV6_ONLY" = "1" ]; then
        _regex_ipv6="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+inet6 ([[:alnum:]:]+)"
        while read -r _line; do
            [[ $_line =~ $_regex_ipv6 ]]
            if [ "${BASH_REMATCH[1]}" != "lo" ] && [ "${BASH_REMATCH[1]}" != "kube-ipvs0" ] && [ "${BASH_REMATCH[1]}" != "docker0" ] && [ "${BASH_REMATCH[1]}" != "weave" ] && [ "${BASH_REMATCH[1]}" != "antrea-gw0" ] && [ "${BASH_REMATCH[1]}" != "flannel.1" ] && [ "${BASH_REMATCH[1]}" != "cni0" ]; then
                _iface_names[$((_count))]=${BASH_REMATCH[1]}
                _iface_addrs[$((_count))]=${BASH_REMATCH[2]}
                let "_count += 1"
            fi
        done <<< "$(ip -6 -o addr)"
    else
        _regex_ipv4="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+[[:alnum:]]+ ([[:digit:].]+)"
        while read -r _line; do
            [[ $_line =~ $_regex_ipv4 ]]
            if [ "${BASH_REMATCH[1]}" != "lo" ] && [ "${BASH_REMATCH[1]}" != "kube-ipvs0" ] && [ "${BASH_REMATCH[1]}" != "docker0" ] && [ "${BASH_REMATCH[1]}" != "weave" ] && [ "${BASH_REMATCH[1]}" != "antrea-gw0" ] && [ "${BASH_REMATCH[1]}" != "flannel.1" ] && [ "${BASH_REMATCH[1]}" != "cni0" ]; then
                _iface_names[$((_count))]=${BASH_REMATCH[1]}
                _iface_addrs[$((_count))]=${BASH_REMATCH[2]}
                let "_count += 1"
            fi
        done <<< "$(ip -4 -o addr)"
    fi


    if [ "$_count" -eq "0" ]; then
        echo >&2 "Error: The installer couldn't discover any valid network interfaces on this machine."
        echo >&2 "Check your network configuration and re-run this script again."
        echo >&2 "If you want to skip this discovery process, pass the 'private-address' arg to this script, e.g. 'sudo ./install.sh private-address=1.2.3.4'"
        exit 1
    elif [ "$_count" -eq "1" ]; then
        PRIVATE_ADDRESS=${_iface_addrs[0]}
        printf "The installer will use network interface '%s' (with IP address '%s')\n" "${_iface_names[0]}" "${_iface_addrs[0]}"
        return
    fi

    if ! prompts_can_prompt ; then
        bail "Multiple network interfaces present, please select an IP address. Try passing the selected address to this script e.g. 'sudo ./install.sh private-address=1.2.3.4' or assign an IP address to the privateAddress field in the kurl add-on."
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
