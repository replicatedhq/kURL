#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/tasks.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/host-packages.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/longhorn.sh
. $DIR/scripts/distro/interface.sh
. $DIR/scripts/distro/kubeadm/distro.sh
. $DIR/scripts/distro/rke2/distro.sh
# Magic end

K8S_DISTRO=
function tasks() {
    DOCKER_VERSION="$(get_docker_version)"

    K8S_DISTRO=kubeadm
    if [ -d "/etc/rancher/rke2" ]; then
        K8S_DISTRO=rke2
    elif [ -d "/etc/rancher/k3s" ]; then
        K8S_DISTRO=k3s
    fi

    case "$1" in
        load-images|load_images)
            load_all_images $@
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
        taint-primaries|taint_primaries)
            taint_primaries
            ;;
        migrate-pvcs|migrate_pvcs)
            migrate_pvcs $@
            ;;
        migrate-rgw-to-minio|migrate_rgw_to_minio)
            migrate_rgw_to_minio_task $@
            ;;
        remove-rook-ceph|remove_rook_ceph)
            remove_rook_ceph_task
            ;;
        longhorn-node-initilize|longhorn_node_initilize)
            install_host_dependencies_longhorn $@
            ;;
        *)
            bail "Unknown task: $1"
            ;;
    esac

    # terminate the script if a task was run
    exit 0
}

function load_all_images() {
    # get params - specifically need kurl-install-directory, as they impact load images scripts
    shift # the first param is load_images/load-images
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

    move_airgap_assets # this is always airgap
    pushd_install_directory

    if [ -n "$DOCKER_VERSION" ]; then
        find addons/ packages/ -type f -wholename '*/images/*.tar.gz' | xargs -I {} bash -c "docker load < {}"
        if [ -f shared/kurl-util.tar ]; then
            docker load < shared/kurl-util.tar
        fi
    else
        # TODO(ethan): rke2 containerd.sock path is incorrect
        find addons/ packages/ -type f -wholename '*/images/*.tar.gz' | xargs -I {} bash -c "cat {} | gunzip | ctr -n=k8s.io images import -"
        if [ -f shared/kurl-util.tar ]; then
            ctr -n=k8s.io images import shared/kurl-util.tar
        fi
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

    discover

    if [ -f /opt/ekco/shutdown.sh ]; then
        bash /opt/ekco/shutdown.sh
    fi

    if commandExists "kubeadm"; then
        printf "Resetting kubeadm\n"
        kubeadm_reset
    fi 

    if commandExists "rke2"; then
        printf "Resetting rke2\n"
        rke2_reset
    fi  

    printf "Removing kubernetes packages\n"
    case "$LSB_DIST" in
        ubuntu)
            apt remove -y kubernetes-cni kubelet kubectl
        ;;

        centos|rhel|amzn|ol)
            yum remove -y kubernetes-cni kubelet kubectl
        ;;

        *)
            echo "Could not uninstall kuberentes host packages on ${LSB_DIST} ${DIST_MAJOR}"
        ;;
    esac

    printf "Removing host files\n"
    rm -rf /etc/cni
    rm -rf /etc/kubernetes
    rm -rf /opt/cni
    rm -rf /opt/replicated
    rm -f /usr/local/bin/helm /usr/local/bin/helmfile
    rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl /usr/bin/crtctl
    rm -f /usr/local/bin/kustomize*
    rm -rf /var/lib/calico
    rm -rf /var/lib/etcd
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/rook
    rm -rf /var/lib/weave
    rm -rf /var/lib/longhorn
    rm -rf /etc/haproxy

    printf "Reset script completed\n"
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
    common_flags="${common_flags}$(get_remotes_flags)"

    local prefix=
    prefix="$(build_installer_prefix "${installer_id}" "${KURL_VERSION}" "${kurl_url}" "")"

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
            weave_version="2.6.5"
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

function taint_primaries() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    # Rook tolerations
    if kubectl get namespace rook-ceph &>/dev/null; then
        kubectl -n rook-ceph patch cephclusters rook-ceph --type=merge -p '{"spec":{"placement":{"all":{"tolerations":[{"key":"node-role.kubernetes.io/master","operator":"Exists"}]}}}}'
        cat <<EOF | kubectl -n rook-ceph patch deployment rook-ceph-operator -p "$(cat)"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-ceph-operator
  namespace: rook-ceph
spec:
  template:
    spec:
      tolerations:
        - key: node-role.kubernetes.io/master
          operator: Exists
      containers:
        - name: rook-ceph-operator
          env:
            - name: DISCOVER_TOLERATION_KEY
              value: node-role.kubernetes.io/master
            - name: CSI_PROVISIONER_TOLERATIONS
              value: |
                - key: node-role.kubernetes.io/master
                  operator: Exists
            - name: CSI_PLUGIN_TOLERATIONS
              value: |
                - key: node-role.kubernetes.io/master
                  operator: Exists
EOF
    fi

    # EKCO tolerations
    if kubernetes_resource_exists kurl deployment ekc-operator; then
        kubectl -n kurl patch deployment ekc-operator --type=merge -p '{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/master","operator":"Exists"}]}}}}'
    fi


    # Taint all primaries
    kubectl taint nodes --overwrite --selector=node-role.kubernetes.io/master node-role.kubernetes.io/master=:NoSchedule

    # Delete pods with PVCs so they get rescheduled to worker nodes immediately
    # TODO: delete pods with PVCs on other primaries
    while read -r uid; do
        if [ -z "$uid" ]; then
            # unmounted device
            continue
        fi
        pod=$(kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.uid}{"\t"}{.metadata.namespace}{"\n"}{end}' | grep "$uid" )
        kubectl delete pod "$(echo "$pod" | awk '{ print $1 }')" --namespace="$(echo "$pod" | awk '{ print $3 }')" --wait=false
    done < <(lsblk | grep '^rbd[0-9]' | awk '{ print $7 }' | awk -F '/' '{ print $6 }')

    # Delete local pods using the Ceph filesystem so they get rescheduled to worker nodes immediately
    while read -r uid; do
        pod=$(kubectl get pods --all-namespaces -ojsonpath='{ range .items[*]}{.metadata.name}{"\t"}{.metadata.uid}{"\t"}{.metadata.namespace}{"\n"}{end}' | grep "$uid" )
        kubectl delete pod "$(echo "$pod" | awk '{ print $1 }')" --namespace="$(echo "$pod" | awk '{ print $3 }')" --wait=false
    done < <(grep ':6789:/' /proc/mounts | grep -v globalmount | awk '{ print $2 }' | awk -F '/' '{ print $6 }')
}

function migrate_pvcs() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    # get params - specifically need airgap as that impacts binary downloads and skip-rook-health-checks to skip rook health checks
    shift # the first param is migrate_pvcs/migrate-pvcs
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            airgap)
                AIRGAP="1"
                ;;
            skip-rook-health-checks)
                SKIP_ROOK_HEALTH_CHECKS="1"
                ;;
            skip-longhorn-health-checks)
                SKIP_LONGHORN_HEALTH_CHECKS="1"
                ;;
            *)
                echo >&2 "Error: unknown parameter \"$_param\""
                exit 1
                ;;
        esac
        shift
    done

    download_util_binaries

    # check that rook-ceph is healthy
    ROOK_CEPH_EXEC_TARGET=rook-ceph-operator
    if kubectl get deployment -n rook-ceph rook-ceph-tools &>/dev/null; then
        ROOK_CEPH_EXEC_TARGET=rook-ceph-tools
    fi
    CEPH_HEALTH_DETAIL=$(kubectl exec -n rook-ceph deployment/$ROOK_CEPH_EXEC_TARGET -- ceph health detail)
    if [ "$CEPH_HEALTH_DETAIL" != "HEALTH_OK" ]; then
        if [ "$SKIP_ROOK_HEALTH_CHECKS" = "1" ]; then
            echo "Continuing with unhealthy rook due to skip-rook-health-checks flag"
        else
            echo "Ceph is not healthy, please resolve this before rerunning the script or rerun with the skip-rook-health-checks flag:"
            echo "$CEPH_HEALTH_DETAIL"
            return 1
        fi
    else
        echo "rook-ceph appears to be healthy"
    fi
    CEPH_DISK_USAGE_TOTAL=$(kubectl exec -n rook-ceph deployment/$ROOK_CEPH_EXEC_TARGET -- ceph df | grep TOTAL | awk '{ print $8$9 }')

    # check that longhorn is healthy
    LONGHORN_NODES_STATUS=$(kubectl get nodes.longhorn.io -n longhorn-system -o=jsonpath='{.items[*].status.conditions.Ready.status}')
    LONGHORN_NODES_SCHEDULABLE=$(kubectl get nodes.longhorn.io -n longhorn-system -o=jsonpath='{.items[*].status.conditions.Schedulable.status}')
    pat="^True( True)*$" # match "True", "True True" etc but not "False True" or ""
    if [[ $LONGHORN_NODES_STATUS =~ $pat ]] && [[ $LONGHORN_NODES_SCHEDULABLE =~ $pat ]]; then
        echo "All Longhorn nodes are ready and schedulable"
    else
        if [ "$SKIP_LONGHORN_HEALTH_CHECKS" = "1" ]; then
            echo "Continuing with unhealthy Longhorn due to skip-longhorn-health-checks flag"
        else
            echo "Longhorn is not healthy, please resolve this before rerunning the script or rerun with the skip-longhorn-health-checks flag:"
            kubectl get nodes.longhorn.io -n longhorn-system
            return 1
        fi
    fi

    # provide large warning that this will stop the app
    printf "${YELLOW}"
    printf "WARNING: \n"
    printf "\n"
    printf "    This command will attempt to move data from rook-ceph to longhorn.\n"
    printf "\n"
    printf "    As part of this, all pods mounting PVCs will be stopped, taking down the application.\n"
    printf "\n"
    printf "    Copying the data currently stored within rook-ceph will require at least %s of free space across the cluster.\n" "$CEPH_DISK_USAGE_TOTAL"
    printf "    It is recommended to take a snapshot or otherwise back up your data before starting this process.\n${NC}"
    printf "\n"
    printf "Would you like to continue? "

    if ! confirmN; then
        printf "Not migrating\n"
        exit 1
    fi

    rook_ceph_to_longhorn
}

function migrate_rgw_to_minio_task() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    MINIO_NAMESPACE=minio

    shift
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            minio-namespace|minio_namespace)
                MINIO_NAMESPACE="$_value"
                ;;
            *)
                echo >&2 "Error: unknown parameter \"$_param\""
                exit 1
                ;;
        esac
        shift
    done

    migrate_rgw_to_minio
}

function remove_rook_ceph_task() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    # provide large warning that this will delete rook-ceph
    printf "${YELLOW}"
    printf "WARNING: \n"
    printf "\n"
    printf "    This command will delete the rook-ceph storage provider\n${NC}"
    printf "\n"
    printf "Would you like to continue? "

    if ! confirmN; then
        printf "Not removing rook-ceph\n"
        exit 1
    fi

    remove_rook_ceph
}

function install_host_dependencies_longhorn() {
    shift # the first param is longhorn-node-initilize|longhorn_node_initilize
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            airgap)
                AIRGAP="1"
                ;;
            kurl-install-directory)
                if [ -n "$_value" ]; then
                    KURL_INSTALL_DIRECTORY_FLAG="${_value}"
                    KURL_INSTALL_DIRECTORY="$(realpath ${_value})/kurl"
                fi
                ;;
        esac
        shift
    done

    discover

    local cwd="$(pwd)"
    if [ "$(readlink -f $KURL_INSTALL_DIRECTORY)" != "${cwd}/kurl" ]; then
        mkdir -p ${cwd}/kurl
        pushd ${cwd}/kurl
        local pushed="1"
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$DIST_URL" ]; then
        local package="host-longhorn.tar.gz"
        package_download "${package}"
        tar xf "$(package_filepath "${package}")"
    fi

    if [ "$pushed" == "1" ]; then
        popd
    fi

    move_airgap_assets # even if not airgap, download happens in cwd and files need to be moved
    pushd_install_directory

    longhorn_host_init_common "${DIR}/packages/host/longhorn"
}

tasks "$@"
