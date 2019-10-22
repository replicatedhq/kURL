
function flags() {
    while [ "$1" != "" ]; do
        _param="$(echo "$1" | cut -d= -f1)"
        _value="$(echo "$1" | grep '=' | cut -d= -f2-)"
        case $_param in
            airgap)
                # airgap implies "offline docker"
                AIRGAP=1
                NO_PROXY=1
                OFFLINE_DOCKER_INSTALL=1
                ;;
            bypass-storagedriver-warnings|bypass_storagedriver_warnings)
                BYPASS_STORAGEDRIVER_WARNINGS=1
                ;;
            bootstrap-token|bootrap_token)
                BOOTSTRAP_TOKEN="$_value"
                ;;
            bootstrap-token-ttl|bootrap_token_ttl)
                BOOTSTRAP_TOKEN_TTL="$_value"
                ;;
            docker-version|docker_version)
                DOCKER_VERSION="$_value"
                ;;
            ceph-pool-replicas|ceph_pool_replicas)
                CEPH_POOL_REPLICAS="$_value"
                ;;
            hostname-check)
                HOSTNAME_CHECK="$_value"
                ;;
            ha)
                HA_CLUSTER=1
                ;;
            http-proxy|http_proxy)
                PROXY_ADDRESS="$_value"
                ;;
            ip-alloc-range|ip_alloc_range)
                IP_ALLOC_RANGE="$_value"
                ;;
            load-balancer-address|load_balancer_address)
                LOAD_BALANCER_ADDRESS="$_value"
                HA_CLUSTER=1
                ;;
            log-level|log_level)
                LOG_LEVEL="$_value"
                ;;
            no-docker|no_docker)
                SKIP_DOCKER_INSTALL=1
                ;;
            no-proxy|no_proxy)
                NO_PROXY=1
                ;;
            public-address|public_address)
                PUBLIC_ADDRESS="$_value"
                ;;
            private-address|private_address)
                PRIVATE_ADDRESS="$_value"
                ;;
            skip-pull|skip_pull)
                SKIP_DOCKER_PULL=1
                ;;
            kubernetes-namespace|kubernetes_namespace)
                KUBERNETES_NAMESPACE="$_value"
                ;;
            storage-class|storage_class)
                STORAGE_CLASS="$_value"
                ;;
            no-ce-on-ee|no_ce_on_ee)
                NO_CE_ON_EE=1
                ;;
            hard-fail-on-loopback|hard_fail_on_loopback)
                HARD_FAIL_ON_LOOPBACK=1
                ;;
            bypass-firewalld-warning|bypass_firewalld_warning)
                BYPASS_FIREWALLD_WARNING=1
                ;;
            hard-fail-on-firewalld|hard_fail_on_firewalld)
                HARD_FAIL_ON_FIREWALLD=1
                ;;
            disable-contour|disable_contour)
                CONTOUR_VERSION=""
                ;;
            disable-prometheus|disable_prometheus)
                PROMETHEUS_VERSION=""
                ;;
            disable-rook|disable_rook)
                ROOK_VERSION=""
                ;;
            reset)
                RESET=1
                ;;
            force-reset|force_reset)
                FORCE_RESET=1
                ;;
            service-cidr|service_cidr)
                SERVICE_CIDR="$_value"
                ;;
            cluster-dns|cluster_dns)
                CLUSTER_DNS="$_value"
                ;;
            encrypt-network|encrypt_network)
                ENCRYPT_NETWORK="$_value"
                ;;
            additional-no-proxy|additional_no_proxy)
                if [ -z "$ADDITIONAL_NO_PROXY" ]; then
                    ADDITIONAL_NO_PROXY="$_value"
                else
                    ADDITIONAL_NO_PROXY="$ADDITIONAL_NO_PROXY,$_value"
                fi
                ;;
            kubernetes-upgrade-patch-version|kubernetes_upgrade_patch_version)
                K8S_UPGRADE_PATCH_VERSION=1
                ;;
            kubernetes-master-address|kubernetes_master_address)
                KUBERNETES_MASTER_ADDR="$_value"
                ;;
            api-service-address|api_service_address)
                API_SERVICE_ADDRESS="$_value"
                ;;
            insecure)
                INSECURE=1
                ;;
            kubeadm-token|kubeadm_token)
                KUBEADM_TOKEN="$_value"
                ;;
            kubeadm-token-ca-hash|kubeadm_token_ca_hash)
                KUBEADM_TOKEN_CA_HASH="$_value"
                ;;
            kubernetes-version|kubernetes_version)
                if [ -n "$KUBERNETES_VERSION" ] && [ "$_value" != "$KUBERNETES_VERSION" ]; then
                    bail "This script installs $KUBERNETES_VERSION"
                fi
                ;;
            control-plane|control_plane)
                MASTER=1
                ;;
            cert-key|cert_key)
                CERT_KEY="$_value"
                ;;
            task)
                TASK="$_value"
                ;;
            docker-registry-ip|docker_registry_ip)
                DOCKER_REGISTRY_IP="$_value"
                ;;
            kotsadm-hostname|kotsadm_hostname)
                KOTSADM_HOSTNAME="$_value"
                ;;
            *)
                echo >&2 "Error: unknown parameter \"$_param\""
                exit 1
                ;;
        esac
        shift
    done

    parseKubernetesTargetVersion
}

parseKubernetesTargetVersion() {
    semverParse "$KUBERNETES_VERSION"
    KUBERNETES_TARGET_VERSION_MAJOR="$major"
    KUBERNETES_TARGET_VERSION_MINOR="$minor"
    KUBERNETES_TARGET_VERSION_PATCH="$patch"
}
