#!/bin/bash

set -e

# Magic begin: scripts are inlined for distribution. See "make build/tasks.sh"
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/kubeadm/distro.sh
. $DIR/scripts/distro/rke2/distro.sh
# Magic end

function tasks() {
    DOCKER_VERSION="$(get_docker_version)"

    case "$1" in
        load-images|load_images)
            load_all_images
            ;;
        generate-admin-user|generate_admin_user)
            generate_admin_user
            ;;
        reset)
            reset
            ;;
        kotsadm-accept-tls-uploads|kotsadm_accept_tls_uploads)
            kotsadm_accept_tls_uploads
            ;;
        print-registry-login|print_registry_login)
            print_registry_login
            ;;
        join-token|join_token)
            join_token $@
            ;;
        set-kubeconfig-server|set_kubeconfig_server)
            set_kubeconfig_server $2
            ;;
        *)
            bail "Unknown task: $1"
            ;;
    esac

    # terminate the script if a task was run
    exit 0
}

function load_all_images() {
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            kurl-install-directory)
                if [ -n "$_value" ]; then
                    KURL_INSTALL_DIRECTORY_FLAG="${_value}"
                    KURL_INSTALL_DIRECTORY="$(realpath ${_value})/kurl"
                fi
                ;;
        esac
        shift
    done

    if [ "$AIRGAP" = "1" ]; then
        move_airgap_assets
    fi
    pushd_install_directory

    if [ -n "$DOCKER_VERSION" ]; then
        find addons/ packages/ -type f -wholename '*/images/*.tar.gz' | xargs -I {} bash -c "docker load < {}"
    else
        # TODO(ethan): rke2 containerd.sock path is incorrect
        find addons/ packages/ -type f -wholename '*/images/*.tar.gz' | xargs -I {} bash -c "cat {} | gunzip | ctr -n=k8s.io images import -"
    fi

    popd_install_directory
}

function generate_admin_user() {
    # get the last IP address from the SANs because that will be load balancer if defined, else public address if defined, else local
    local ip=$(echo "Q" | openssl s_client -connect=${PRIVATE_ADDRESS}:6443 | openssl x509 -noout -text | grep DNS | awk '{ print $NF }' | awk -F ':' '{ print $2 }')

    if ! isValidIpv4 "$ip"; then
        bail "Failed to parse IP from Kubernetes API Server SANs"
    fi

    local address="https://${ip}:6443"
    local username="${SUDO_USER}"

    openssl req -newkey rsa:2048 -nodes -keyout "${username}.key" -out "${username}.csr" -subj="/CN=${username}/O=system:masters"
    openssl x509 -req -days 365 -sha256 -in "${username}.csr" -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -set_serial 1 -out "${username}.crt"

    # kubectl will create the conf file
    kubectl --kubeconfig="${username}.conf" config set-credentials "${username}" --client-certificate="${username}.crt" --client-key="${username}.key" --embed-certs=true
    rm "${username}.crt" "${username}.csr" "${username}.key"

    kubectl --kubeconfig="${username}.conf" config set-cluster kurl --server="$address" --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true
    kubectl --kubeconfig="${username}.conf" config set-context kurl --cluster=kurl --user="${username}"
    kubectl --kubeconfig="${username}.conf" config use-context kurl

    chown "${username}" "${username}.conf"

    printf "\n"
    printf "${GREEN}Kubeconfig successfully generated. Example usage:\n"
    printf "\n"
    printf "\tkubectl --kubeconfig=${username}.conf get ns${NC}"
    printf "\n"
    printf "\n"
}

# TODO kube-proxy ipvs cleanup
function reset() {
    set +e

    if [ "$FORCE_RESET" != 1 ]; then
        printf "${YELLOW}"
        printf "WARNING: \n"
        printf "\n"
        printf "    The \"reset\" command will attempt to remove kubernetes from this system.\n"
        printf "\n"
        printf "    This command is intended to be used only for \n"
        printf "    increasing iteration speed on development servers. It has the \n"
        printf "    potential to leave your machine in an unrecoverable state. It is \n"
        printf "    not recommended unless you will easily be able to discard this server\n"
        printf "    and provision a new one if something goes wrong.\n${NC}"
        printf "\n"
        printf "Would you like to continue? "

        if ! confirmN; then
            printf "Not resetting\n"
            exit 1
        fi
    fi

    if commandExists "kubeadm"; then
        kubeadm_reset
    fi 

    if commandExists "rke2"; then
        rke2_reset
    fi   
    
    rm -rf /etc/cni
    rm -rf /etc/kubernetes
    rm -rf /opt/cni
    rm -rf /opt/replicated
    rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl
    rm -f /usr/local/bin/kustomize*
    rm -rf /var/lib/calico
    rm -rf /var/lib/etcd
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/rook
    rm -rf /var/lib/weave

    printf "Reset script completed\n"
}

function weave_reset() {
    BRIDGE=weave
    DATAPATH=datapath
    CONTAINER_IFNAME=ethwe

    DOCKER_BRIDGE=docker0

    # https://github.com/weaveworks/weave/blob/05ab1139db615c61b99074c63184076ba72e2416/weave#L460
    for NETDEV in $BRIDGE $DATAPATH ; do
        if [ -d /sys/class/net/$NETDEV ] ; then
            if [ -d /sys/class/net/$NETDEV/bridge ] ; then
                ip link del $NETDEV
            else
                if [ -n "$DOCKER_VERSION" ]; then
                    docker run --rm --pid host --net host --privileged --entrypoint=/usr/bin/weaveutil weaveworks/weaveexec:$WEAVE_TAG delete-datapath $NETDEV
                else
                    # --pid host
                    local guid=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)
                    # TODO(ethan): rke2 containerd.sock path is incorrect
                    ctr -n=k8s.io image pull docker.io/weaveworks/weaveexec:$WEAVE_TAG
                    ctr -n=k8s.io run --rm --net-host --privileged docker.io/weaveworks/weaveexec:$WEAVE_TAG $guid /usr/bin/weaveutil delete-datapath $NETDEV
                fi
            fi
        fi
    done

    # Remove any lingering bridged fastdp, pcap and attach-bridge veths
    for VETH in $(ip -o link show | grep -o v${CONTAINER_IFNAME}[^:@]*) ; do
        ip link del $VETH >/dev/null 2>&1 || true
    done

    if [ "$DOCKER_BRIDGE" != "$BRIDGE" ] ; then
        run_iptables -t filter -D FORWARD -i $DOCKER_BRIDGE -o $BRIDGE -j DROP 2>/dev/null || true
    fi

    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dport 53  -j ACCEPT  >/dev/null 2>&1 || true
    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dport 53  -j ACCEPT  >/dev/null 2>&1 || true

    if [ -n "$DOCKER_VERSION" ]; then
        DOCKER_BRIDGE_IP=$(docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil weaveworks/weaveexec:$WEAVE_TAG bridge-ip $DOCKER_BRIDGE)

        run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
        run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
        run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $(($PORT + 1)) -j DROP >/dev/null 2>&1 || true
    fi

    run_iptables -t filter -D FORWARD -i $BRIDGE ! -o $BRIDGE -j ACCEPT 2>/dev/null || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    run_iptables -t filter -D FORWARD -i $BRIDGE -o $BRIDGE -j ACCEPT 2>/dev/null || true
    run_iptables -F WEAVE-NPC >/dev/null 2>&1 || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -j WEAVE-NPC 2>/dev/null || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -m state --state NEW -j NFLOG --nflog-group 86 2>/dev/null || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -j DROP 2>/dev/null || true
    run_iptables -X WEAVE-NPC >/dev/null 2>&1 || true

    run_iptables -F WEAVE-EXPOSE >/dev/null 2>&1 || true
    run_iptables -t filter -D FORWARD -o $BRIDGE -j WEAVE-EXPOSE 2>/dev/null || true
    run_iptables -X WEAVE-EXPOSE >/dev/null 2>&1 || true

    run_iptables -t nat -F WEAVE >/dev/null 2>&1 || true
    run_iptables -t nat -D POSTROUTING -j WEAVE >/dev/null 2>&1 || true
    run_iptables -t nat -D POSTROUTING -o $BRIDGE -j ACCEPT >/dev/null 2>&1 || true
    run_iptables -t nat -X WEAVE >/dev/null 2>&1 || true

    for LOCAL_IFNAME in $(ip link show | grep v${CONTAINER_IFNAME}pl | cut -d ' ' -f 2 | tr -d ':') ; do
        ip link del ${LOCAL_IFNAME%@*} >/dev/null 2>&1 || true
    done
}

function kotsadm_accept_tls_uploads() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    kubectl patch secret kotsadm-tls -p '{"stringData":{"acceptAnonymousUploads":"1"}}'
}

function print_registry_login() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    local passwd=$(kubectl get secret registry-creds -o=jsonpath='{ .data.\.dockerconfigjson }' | base64 --decode | grep -oE '"password":"\w+"' | awk -F\" '{ print $4 }')
    local clusterIP=$(kubectl -n kurl get service registry -o=jsonpath='{ .spec.clusterIP }')

    if [ -n "$DOCKER_VERSION" ]; then
        printf "${BLUE}Local:${NC}\n"
        printf "${GREEN}docker login --username=kurl --password=$passwd $clusterIP ${NC}\n"
    fi
    printf "${BLUE}Secret:${NC}\n"
    printf "${GREEN}kubectl create secret docker-registry kurl-registry --docker-username=kurl --docker-password=$passwd --docker-server=$clusterIP ${NC}\n"

    if kubectl -n kurl get service registry | grep -q NodePort; then
        # last IP in SANs will be public address if known else private address
        local hostIP=$(echo q | openssl s_client -connect $clusterIP:443 2>/dev/null | openssl x509 -noout -text | grep 'IP Address' | awk -F':' '{ print $NF }')
        local nodePort=$(kubectl -n kurl get service registry -ojsonpath='{ .spec.ports[0].nodePort }')

        printf "\n"
        if [ -n "$DOCKER_VERSION" ]; then
            printf "${BLUE}Remote:${NC}\n"
            printf "${GREEN}mkdir -p /etc/docker/certs.d/$hostIP:$nodePort\n"
            printf "cat > /etc/docker/certs.d/$hostIP:$nodePort/ca.crt <<EOF\n"
            cat /etc/kubernetes/pki/ca.crt
            printf "EOF\n"
            printf "docker login --username=kurl --password=$passwd $hostIP:$nodePort ${NC}\n"
        fi
        printf "${BLUE}Secret:${NC}\n"
        printf "${GREEN}kubectl create secret docker-registry kurl-registry --docker-username=kurl --docker-password=$passwd --docker-server=$hostIP:$nodePort ${NC}\n"
    fi
}

function join_token() {
    # get params - specifically need ha and airgap, as they impact join scripts
    shift # the first param is join_token/join-token
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            airgap)
                AIRGAP="1"
                ;;
            ha)
                HA_CLUSTER="1"
                ;;
            *)
                echo >&2 "Error: unknown parameter \"$_param\""
                exit 1
                ;;
        esac
        shift
    done

    export KUBECONFIG=/etc/kubernetes/admin.conf

    # get ca cert hash, bootstrap token and master address
    local bootstrap_token=$(kubeadm token generate)
    kubeadm token create "$bootstrap_token" --print-join-command 2>/dev/null > /tmp/kubeadm-token
    local kubeadm_ca_hash=$(cat /tmp/kubeadm-token | grep -o 'sha256:[^ ]*')
    local api_service_address=$(cat /tmp/kubeadm-token | awk '{ print $3 }')
    rm /tmp/kubeadm-token

    # get the kurl url and installer id from the kurl-config configmap
    local kurl_url=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.kurl_url }')
    local installer_id=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.installer_id }')

    # upload certs and get the key
    local cert_key
    if [ "$HA_CLUSTER" = "1" ]; then
        # pipe to a file so that the cert key is written out
        kubeadm init phase upload-certs --upload-certs 2>/dev/null > /tmp/kotsadm-cert-key
        cert_key=$(cat /tmp/kotsadm-cert-key | grep -v 'upload-certs' )
        rm /tmp/kotsadm-cert-key
    fi

    # get the kubernetes version
    local kubernetes_version=$(kubectl version --short | grep -i server | awk '{ print $3 }' | sed 's/^v*//')

    local service_cidr=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.service_cidr }')
    local pod_cidr=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.pod_cidr }')
    local kurl_install_directory=$(kubectl -n kube-system get cm kurl-config -ojsonpath='{ .data.kurl_install_directory }')
    local docker_registry_ip=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")

    local common_flags
    common_flags="${common_flags}$(get_docker_registry_ip_flag "${docker_registry_ip}")"
    if [ -n "$service_cidr" ] && [ -n "$pod_cidr" ]; then
        common_flags="${common_flags}$(get_additional_no_proxy_addresses_flag "1" "${service_cidr},${pod_cidr}")"
    fi
    common_flags="${common_flags}$(get_kurl_install_directory_flag "${kurl_install_directory}")"

    # build the installer prefix
    local prefix="curl -sSL $kurl_url/$installer_id/"
    if [ -z "$kurl_url" ]; then
        prefix="cat "
    fi

    if [ "$HA_CLUSTER" = "1" ]; then
        printf "Master node join commands expire after two hours, and worker node join commands expire after 24 hours.\n"
        printf "\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "To generate new node join commands, run ${GREEN}cat ./tasks.sh | sudo bash -s join_token ha airgap${NC} on an existing master node.\n"
        else 
            printf "To generate new node join commands, run ${GREEN}${prefix}tasks.sh | sudo bash -s join_token ha${NC} on an existing master node.\n"
        fi
    else
        printf "Node join commands expire after 24 hours.\n"
        printf "\n"
        if [ "$AIRGAP" = "1" ]; then
            printf "To generate new node join commands, run ${GREEN}cat ./tasks.sh | sudo bash -s join_token airgap${NC} on this node.\n"
        else 
            printf "To generate new node join commands, run ${GREEN}${prefix}tasks.sh | sudo bash -s join_token${NC} on this node.\n"
        fi
    fi

    if [ "$AIRGAP" = "1" ]; then
        printf "\n"
        printf "To add worker nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
        printf "\n"
        printf "\n"
        printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${api_service_address} kubeadm-token=${bootstrap_token} kubeadm-token-ca-hash=${kubeadm_ca_hash} kubernetes-version=${kubernetes_version}${common_flags}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, copy and unpack this bundle on your other nodes, and run the following:"
            printf "\n"
            printf "\n"
            printf "${GREEN}    cat ./join.sh | sudo bash -s airgap kubernetes-master-address=${api_service_address} kubeadm-token=${bootstrap_token} kubeadm-token-ca-hash=${kubeadm_ca_hash} kubernetes-version=${kubernetes_version} cert-key=${cert_key} control-plane${common_flags}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    else
        printf "\n"
        printf "To add worker nodes to this installation, run the following script on your other nodes:"
        printf "\n"
        printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${api_service_address} kubeadm-token=${bootstrap_token} kubeadm-token-ca-hash=${kubeadm_ca_hash} kubernetes-version=${kubernetes_version}${common_flags}\n"
        printf "${NC}"
        printf "\n"
        printf "\n"
        if [ "$HA_CLUSTER" = "1" ]; then
            printf "\n"
            printf "To add ${GREEN}MASTER${NC} nodes to this installation, run the following script on your other nodes:"
            printf "\n"
            printf "${GREEN}    ${prefix}join.sh | sudo bash -s kubernetes-master-address=${api_service_address} kubeadm-token=${bootstrap_token} kubeadm-token-ca-hash=$kubeadm_ca_hash kubernetes-version=${kubernetes_version} cert-key=${cert_key} control-plane${common_flags}\n"
            printf "${NC}"
            printf "\n"
            printf "\n"
        fi
    fi
}

function get_docker_version() {
    if ! commandExists "docker" ; then
        return
    fi
    docker -v 2>/dev/null | awk '{gsub(/,/, "", $3); print $3}'
}

function get_weave_version() {
    local weave_version=$(KUBECONFIG=/etc/kubernetes/admin.conf kubectl get daemonset -n kube-system weave-net -o jsonpath="{..spec.containers[0].image}" | sed 's/^.*://')
    if [ -z "$weave_version" ]; then
        if [ -n "$DOCKER_VERSION" ]; then
            weave_version=$(docker image ls | grep weaveworks/weave-npc | awk '{ print $2 }' | head -1)
        else
            weave_version=$(crictl images list | grep weaveworks/weave-npc | awk '{ print $2 }' | head -1)
        fi
        if [ -z "$weave_version" ]; then
            # if we don't know the exact weave tag, use a sane default
            weave_version="2.7.0"
        fi
    fi
    echo $weave_version
}

function set_kubeconfig_server() {
    local server="$1"
    if [ -z "$server" ]; then
        bail "usage: cat tasks.sh | sudo bash -s set-kubeconfig-server <load-balancer-address>"
    fi

    # on K8s 1.19+ the scheduler and controller-manager kubeconfigs point to the local API server even
    # when a load balancer is being used
    semverParse $(kubeadm version --output=short | sed 's/v//')
    if [ $minor -lt 19 ]; then
        if [ -f "/etc/kubernetes/scheduler.conf" ]; then
            while read -r cluster; do
                kubectl --kubeconfig=/etc/kubernetes/scheduler.conf config set-cluster "$cluster" --server "$server"
            done < <(kubectl --kubeconfig /etc/kubernetes/scheduler.conf config get-clusters | grep -v NAME)
            # restart
            mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/ && sleep 1 && mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
        fi

        if [ -f "/etc/kubernetes/controller-manager.conf" ]; then
            while read -r cluster; do
                kubectl --kubeconfig=/etc/kubernetes/controller-manager.conf config set-cluster "$cluster" --server "$server"
            done < <(kubectl --kubeconfig /etc/kubernetes/controller-manager.conf config get-clusters | grep -v NAME)
            mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/ && sleep 1 && mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
        fi
    fi

    while read -r cluster; do
        kubectl --kubeconfig=/etc/kubernetes/kubelet.conf config set-cluster "$cluster" --server "$server"
    done < <(kubectl --kubeconfig /etc/kubernetes/kubelet.conf config get-clusters | grep -v NAME)
    systemctl restart kubelet

    if [ -f "/etc/kubernetes/admin.conf" ]; then
        while read -r cluster; do
            kubectl --kubeconfig=/etc/kubernetes/admin.conf config set-cluster "$cluster" --server "$server"
        done < <(kubectl --kubeconfig /etc/kubernetes/admin.conf config get-clusters | grep -v NAME)
    fi
}

tasks "$@"
