
function tasks() {
    if [ -z "$TASK" ]; then
        return 0
    fi

    case "$TASK" in
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
        kotsadm-change-password|kotsadm_change_password)
            kotsadm_change_password
            ;;
        *)
            bail "Unknown task: $TASK"
            ;;
    esac

    # terminate the script if a task was run
    exit 0
}

function load_all_images() {
    find addons/ packages/ -type f -wholename '*/images/*.tar.gz' | xargs -I {} bash -c "docker load < {}"
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
    kubectl --kubeconfig=areed.conf config set-context kurl --cluster=kurl --user=areed
    kubectl --kubeconfig=areed.conf config use-context kurl

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
        kubeadm reset --force
    fi

    weave_reset

    rm -rf /var/lib/weave
    rm -rf /opt/replicated
    rm -rf /opt/cni
    rm -rf /etc/kubernetes
    rm -rf /var/lib/rook
    rm -rf /var/lib/etcd
    rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl
    rm -rf /var/lib/kubelet
}

function weave_reset() {
    BRIDGE=weave
    DATAPATH=datapath
    CONTAINER_IFNAME=ethwe

    WEAVE_TAG=${WEAVE_VERSION}
    DOCKER_BRIDGE=docker0

    DOCKER_BRIDGE_IP=$(docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil weaveworks/weaveexec:$WEAVE_TAG bridge-ip $DOCKER_BRIDGE)

    # https://github.com/weaveworks/weave/blob/05ab1139db615c61b99074c63184076ba72e2416/weave#L460
    for NETDEV in $BRIDGE $DATAPATH ; do
        if [ -d /sys/class/net/$NETDEV ] ; then
            if [ -d /sys/class/net/$NETDEV/bridge ] ; then
                ip link del $NETDEV
            else
                docker run --rm --pid host --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=/usr/bin/weaveutil weaveworks/weaveexec:$WEAVE_TAG delete-datapath $NETDEV
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

    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p tcp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $PORT          -j DROP >/dev/null 2>&1 || true
    run_iptables -t filter -D INPUT -i $DOCKER_BRIDGE -p udp --dst $DOCKER_BRIDGE_IP --dport $(($PORT + 1)) -j DROP >/dev/null 2>&1 || true

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
    kubectl patch secret kotsadm-tls -p '{"stringData":{"acceptAnonymousUploads":"1"}}'
}

function print_registry_login() {
    local passwd=$(kubectl get secret registry-creds -o=jsonpath='{ .data.\.dockerconfigjson }' | base64 --decode | grep -oE '"password":"\w+"' | awk -F\" '{ print $4 }')
    local clusterIP=$(kubectl -n kurl get service registry -o=jsonpath='{ .spec.clusterIP }')

    printf "${BLUE}Local:${NC}\n"
    printf "${GREEN}docker login --username=kurl --password=$passwd $clusterIP ${NC}\n"
    printf "${BLUE}Secret:${NC}\n"
    printf "${GREEN}kubectl create secret docker-registry kurl-registry --docker-username=kurl --docker-password=$passwd --docker-server=$clusterIP ${NC}\n"

    if kubectl -n kurl get service registry | grep -q NodePort; then
        # last IP in SANs will be public address if known else private address
        local hostIP=$(echo q | openssl s_client -connect $clusterIP:443 2>/dev/null | openssl x509 -noout -text | grep 'IP Address' | awk -F':' '{ print $NF }')
        local nodePort=$(kubectl -n kurl get service registry -ojsonpath='{ .spec.ports[0].nodePort }')

        printf "\n"
        printf "${BLUE}Remote:${NC}\n"
        printf "${GREEN}mkdir -p /etc/docker/certs.d/$hostIP:$nodePort\n"
        printf "cat > /etc/docker/certs.d/$hostIP:$nodePort/ca.crt <<EOF\n"
        cat /etc/kubernetes/pki/ca.crt
        printf "EOF\n"
        printf "docker login --username=kurl --password=$passwd $hostIP:$nodePort ${NC}\n"
        printf "${BLUE}Secret:${NC}\n"
        printf "${GREEN}kubectl create secret docker-registry kurl-registry --docker-username=kurl --docker-password=$passwd --docker-server=$hostIP:$nodePort ${NC}\n"
    fi
}

function kotsadm_change_password() {
    KOTSADM_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    BCRYPT_PASSWORD=$(docker run --rm epicsoft/bcrypt:latest hash "$KOTSADM_PASSWORD" 14)

    kubectl delete secret kotsadm-password
    kubectl create secret generic kotsadm-password --from-literal=passwordBcrypt=$BCRYPT_PASSWORD

    printf "password: ${GREEN}${KOTSADM_PASSWORD}${NC}\n"

    kubectl delete pod --selector=app=kotsadm-api
}
