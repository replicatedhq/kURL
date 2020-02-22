
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
            ceph-replica-count|ceph_replica_count)
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
                POD_CIDR="$_value"
                ;;
            load-balancer-address|load_balancer_address)
                LOAD_BALANCER_ADDRESS="$_value"
                HA_CLUSTER=1
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
            storage-class|storage_class)
                STORAGE_CLASS="$_value"
                ;;
            storage-class-name|storage_class_name)
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
            fluentd-full-efk-stack|fluentd_full_efk_stack)
                FLUENTD_FULL_EFK_STACK=1
                ;;
            service-cidr|service_cidr)
                SERVICE_CIDR="$_value"
                ;;
            encrypt-network|encrypt_network)
                ENCRYPT_NETWORK="$_value"
                ;;
            disable-weave-encryption|disable_weave_encryption)
                ENCRYPT_NETWORK="0"
                ;;
            additional-no-proxy|additional_no_proxy)
                if [ -z "$ADDITIONAL_NO_PROXY" ]; then
                    ADDITIONAL_NO_PROXY="$_value"
                else
                    ADDITIONAL_NO_PROXY="$ADDITIONAL_NO_PROXY,$_value"
                fi
                ;;
            kubernetes-master-address|kubernetes_master_address)
                KUBERNETES_MASTER_ADDR="$_value"
                ;;
            api-service-address|api_service_address)
                API_SERVICE_ADDRESS="$_value"
                ;;
            kubeadm-token|kubeadm_token)
                KUBEADM_TOKEN="$_value"
                ;;
            kubeadm-token-ca-hash|kubeadm_token_ca_hash)
                KUBEADM_TOKEN_CA_HASH="$_value"
                ;;
            kubernetes-version|kubernetes_version)
                local k8sversion=$(echo "$_value" | sed 's/v//')
                if [ -n "$KUBERNETES_VERSION" ] && [ "$k8sversion" != "$KUBERNETES_VERSION" ]; then
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
            kotsadm-application-slug|kotsadm_application_slug)
                KOTSADM_APPLICATION_SLUG="$_value"
                ;;
            kotsadm-ui-bind-port|kotsadm_ui_bind_port)
                KOTSADM_UI_BIND_PORT="$_value"
                ;;
            pod-cidr|pod_cidr)
                POD_CIDR="$_value"
                IP_ALLOC_RANGE="$_value"
                ;;
            service-cidr|service_cidr)
                SERVICE_CIDR="$_value"
                ;;
            registry-publish-port|registry_publish_port)
                REGISTRY_PUBLISH_PORT="$_value"
                ;;
            kotsadm-application-namespaces|kotsadm_application_namespaces)
                KOTSADM_APPLICATION_NAMESPACES="$_value"
                ;;
            velero-namespace|velero_namespace)
                VELERO_NAMESPACE="$_value"
                ;;
            velero-local-bucket|velero_local_bucket)
                VELERO_LOCAL_BUCKET="$_value"
                ;;
            velero-disable-cli|velero_disable_cli)
                VELERO_DISABLE_CLI=1
                ;;
            velero-disable-restic|velero_disable_restic)
                VELERO_DISABLE_RESTIC=1
                ;;
            kotsadm-alpha|kotsadm_alpha)
                KOTSADM_VERSION=alpha
                ;;
            minio-namespace|minio_namespace)
                MINIO_NAMESPACE="$_value"
                ;;
            openebs-namespace|openebs_namespace)
                OPENEBS_NAMESPACE="$_value"
                ;;
            openebs-localpv|openebs_localpv)
                OPENEBS_LOCALPV=1
                ;;
            openebs-localpv-storage-class|openebs_localpv_storage_class)
                OPENEBS_LOCALPV_STORAGE_CLASS="$_value"
                ;;
            pod-cidr-range|pod_cidr_range)
                # allow either /16 or 16 for subnet size
                POD_CIDR_RANGE=$(echo "$_value" | sed "s/\///")
                ;;
            service-cidr-range|service_cidr_range)
                # allow either /16 or 16 for subnet size
                SERVICE_CIDR_RANGE=$(echo "$_value" | sed "s/\///")
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
