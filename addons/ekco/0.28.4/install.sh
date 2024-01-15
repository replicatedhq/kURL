#!/usr/bin/env bash

EKCO_HAPROXY_IMAGE=haproxy:2.9.2-alpine3.19

EKCO_ROOK_PRIORITY_CLASS=
function ekco_pre_init() {
    if [ -z "$EKCO_NODE_UNREACHABLE_TOLERATION_DURATION" ]; then
        EKCO_NODE_UNREACHABLE_TOLERATION_DURATION=5m
    fi
    if [ -z "$EKCO_MIN_READY_MASTER_NODE_COUNT" ]; then
        EKCO_MIN_READY_MASTER_NODE_COUNT=2
    fi
    if [ -z "$EKCO_MIN_READY_WORKER_NODE_COUNT" ]; then
        EKCO_MIN_READY_WORKER_NODE_COUNT=0
    fi
    EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=true
    if [ -z "$ROOK_VERSION" ] || [ "$EKCO_ROOK_SHOULD_USE_ALL_NODES" = "1" ]; then
        EKCO_SHOULD_MAINTAIN_ROOK_STORAGE_NODES=false
    fi
    EKCO_RECONCILE_ROOK_MDS_PLACEMENT=true
    if [ -z "$ROOK_VERSION" ] || [ "$EKCO_ROOK_SHOULD_DISABLE_RECONCILE_MDS_PLACEMENT" = "1" ]; then
        EKCO_RECONCILE_ROOK_MDS_PLACEMENT=false
    fi
    EKCO_RECONCILE_CEPH_CSI_RESOURCES=true
    if [ -z "$ROOK_VERSION" ] || [ "$EKCO_ROOK_SHOULD_DISABLE_RECONCILE_CEPH_CSI_RESOURCES" = "1" ]; then
        EKCO_RECONCILE_CEPH_CSI_RESOURCES=false
    fi
    EKCO_SHOULD_INSTALL_REBOOT_SERVICE=1
    if [ "$EKCO_SHOULD_DISABLE_REBOOT_SERVICE" = "1" ]; then
        EKCO_SHOULD_INSTALL_REBOOT_SERVICE=0
    fi
    EKCO_PURGE_DEAD_NODES=false
    if [ "$EKCO_SHOULD_ENABLE_PURGE_NODES" = "1" ]; then
        EKCO_PURGE_DEAD_NODES=true
    fi
    EKCO_CLEAR_DEAD_NODES=true
    if [ "$EKCO_SHOULD_DISABLE_CLEAR_NODES" = "1" ]; then
        EKCO_CLEAR_DEAD_NODES=false
    fi
    if [ "$ROOK_VERSION" = "1.0.4" ]; then
        EKCO_ROOK_PRIORITY_CLASS="node-critical"
    fi
    EKCO_RESTART_FAILED_ENVOY_PODS=true
    if [ -z "$CONTOUR_VERSION" ] || [ "$EKCO_SHOULD_DISABLE_RESTART_FAILED_ENVOY_PODS" = "1" ]; then
        EKCO_RESTART_FAILED_ENVOY_PODS=false
    fi
    if [ -z "$EKCO_ENVOY_PODS_NOT_READY_DURATION" ]; then
        EKCO_ENVOY_PODS_NOT_READY_DURATION="5m"
    fi

    EKCO_ENABLE_INTERNAL_LOAD_BALANCER_BOOL=false
    if [ "$EKCO_ENABLE_INTERNAL_LOAD_BALANCER" = "1" ]; then
        EKCO_ENABLE_INTERNAL_LOAD_BALANCER_BOOL=true
        HA_CLUSTER=1
        LOAD_BALANCER_ADDRESS=localhost
        LOAD_BALANCER_PORT="6444"
    fi

    EKCO_MAINTAIN_MINIO=false
    if [ -n "$MINIO_VERSION" ] && [ -n "$OPENEBS_LOCALPV" ] && [ "$EKCO_MINIO_SHOULD_DISABLE_MANAGEMENT" != "1" ]; then
        EKCO_MAINTAIN_MINIO=true
    fi

    EKCO_MAINTAIN_KOTSADM=false
    if [ -n "$KOTSADM_VERSION" ] && [ -n "$OPENEBS_LOCALPV" ] && [ "$EKCO_KOTSADM_SHOULD_DISABLE_MANAGEMENT" != "1" ]; then
        EKCO_MAINTAIN_KOTSADM=true
    fi
}

function ekco_post_init() {
    local primary_ip=
    local control_plane_label=
    control_plane_label="$(kubernetes_get_control_plane_label)"
    primary_ip=$(kubectl get nodes --no-headers --selector="$control_plane_label" -owide | awk '{ print $6 }' | head -n 1)
    if [ -n "${primary_ip}" ]; then
        # global variable EKCO_ADDRESS is used as an argument to the join.sh command
        # shellcheck disable=SC2034
        EKCO_ADDRESS="${primary_ip}:${EKCO_NODE_PORT}"
    fi
}

function ekco() {
    local src="$DIR/addons/ekco/$EKCO_VERSION"
    local dst="$DIR/kustomize/ekco"

    ekco_dynamicstorage

    ekco_create_deployment "$src" "$dst"

    if [ "$EKCO_SHOULD_INSTALL_REBOOT_SERVICE" = "1" ]; then
        ekco_install_reboot_service "$src"
    fi

    ekco_install_purge_node_command "$src"

    # Wait for the pod image override mutating webhook to be created so when other add-ons are
    # installed they will get their overridden image
    if [ -n "$EKCO_POD_IMAGE_OVERRIDES" ]; then
        ekco_load_images
        log "Waiting up to 5 minutes for pod-image-overrides mutating webhook config to be created"
        if ! spinner_until 300 kubernetes_resource_exists kurl mutatingwebhookconfigurations pod-image-overrides.kurl.sh; then
            bail "EKCO failed to deploy the pod-image-overrides.kurl.sh mutating webhook configuration"
        fi
    fi

    ekco_maybe_remove_rook_priority_class_label
}

function ekco_join() {
    local src="$DIR/addons/ekco/$EKCO_VERSION"

    EKCO_SHOULD_INSTALL_REBOOT_SERVICE=1
    if [ "$EKCO_SHOULD_DISABLE_REBOOT_SERVICE" = "1" ]; then
        EKCO_SHOULD_INSTALL_REBOOT_SERVICE=0
    fi

    if [ "$EKCO_SHOULD_INSTALL_REBOOT_SERVICE" = "1" ]; then
        ekco_install_reboot_service "$src"
    fi

    if kubernetes_is_master; then
        ekco_install_purge_node_command "$src"
    fi

    if [ "$EKCO_ENABLE_INTERNAL_LOAD_BALANCER" = "1" ]; then
        ekco_bootstrap_internal_lb
    fi

    ekco_load_images
}

function ekco_already_applied() {
    local src="$DIR/addons/ekco/$EKCO_VERSION"
    local dst="$DIR/kustomize/ekco"

    # if rook-ceph has been removed, ekco should be redeployed to not attempt to manage it
    if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ]; then
        ekco_create_deployment "$src" "$dst"
    fi

    # check if EKCO deployment needs to be scaled up after a Rook upgrade
    ekco_maybe_scaleup_operator

    ekco_maybe_remove_rook_priority_class_label
}

function ekco_maybe_scaleup_operator() {
    local ekcoReplicas=
    ekcoReplicas=$(kubectl -n kurl get deployment ekc-operator -o jsonpath='{.spec.replicas}')

    if [ -z "$ekcoReplicas" ] || [ "$ekcoReplicas" -eq 0 ]; then
        log "Scaling up EKCO operator deployment"
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi
}

# ekco_maybe_remove_rook_priority_class_label will remove the rook-priority.kurl.sh label
# indicating that the EKCO rook-priority.kurl.sh mutating webhook should no longer be applied
# to the rook-ceph namespace.
function ekco_maybe_remove_rook_priority_class_label() {
    if kubectl get namespace rook-ceph >/dev/null 2>&1 ; then
        if [ -z "$EKCO_ROOK_PRIORITY_CLASS" ]; then
            kubectl label namespace rook-ceph rook-priority.kurl.sh-
        fi
    fi
}

function ekco_install_reboot_service() {
    local src="$1"

    logStep "Installing ekco reboot service"

    mkdir -p /opt/ekco
    cp "$src/reboot/startup.sh" /opt/ekco/startup.sh
    cp "$src/reboot/shutdown.sh" /opt/ekco/shutdown.sh
    if [ -n "$DOCKER_VERSION" ]; then
        cp "$src/reboot/ekco-reboot.service" /etc/systemd/system/ekco-reboot.service
    else
        cp "$src/reboot/ekco-reboot-containerd.service" /etc/systemd/system/ekco-reboot.service
    fi
    chmod u+x /opt/ekco/startup.sh
    chmod u+x /opt/ekco/shutdown.sh

    systemctl daemon-reload
    systemctl enable ekco-reboot.service
    if ! timeout 30s systemctl start ekco-reboot.service; then
        log "Failed to start ekco-reboot.service within 30s, restarting it"
        systemctl restart ekco-reboot.service
    fi

    logSuccess "ekco reboot service installed"
}

function ekco_install_purge_node_command() {
    local src="$1"

    logStep "Installing ekco purge node command"

    cp "$src/ekco-purge-node.sh" /usr/local/bin/ekco-purge-node
    chmod u+x /usr/local/bin/ekco-purge-node

    logSuccess "ekco purge node command installed"
}

function ekco_handle_load_balancer_address_change_pre_init() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 0
    fi

    splitHostPort $1
    local oldLoadBalancerHost=$HOST
    splitHostPort $2
    local newLoadBalancerHost=$HOST

    if [ "$oldLoadBalancerHost" = "$newLoadBalancerHost" ]; then
        return 0
    fi

    local ARG=--add-alt-names=$newLoadBalancerHost

    for NODE in "${KUBERNETES_REMOTE_PRIMARIES[@]}"; do
        logStep "Adding new load balancer $newLoadBalancerHost to API server certificate on node $NODE"
        local podName=regen-cert-$NODE
        kubectl delete pod $podName --force --grace-period=0 2>/dev/null || true
        render_yaml_file "$DIR/addons/ekco/$EKCO_VERSION/regen-cert-pod.yaml" | kubectl apply -f -
        spinner_until 120 kubernetes_pod_started $podName default
        kubectl logs -f $podName
        spinner_until 10 kubernetes_pod_completed $podName default
        local phase=$(kubectl get pod $podName -ojsonpath='{ .status.phase }')
        if [ "$phase" != "Succeeded" ]; then
            bail "Pod $podName phase: $phase"
        fi
        kubectl delete pod $podName --force --grace-period=0
    done

    # Wait for the servers to pick up the new certs
    for NODE in "${KUBERNETES_REMOTE_PRIMARIES[@]}"; do
        local nodeIP=$(kubectl get node $NODE -owide  --no-headers | awk '{ print $6 }')
        log "Waiting for $NODE to begin serving certificate signed for $newLoadBalancerHost"
        local addr=$($DIR/bin/kurl format-address $nodeIP)
        if ! spinner_until 120 cert_has_san "$addr:6443" "$newLoadBalancerHost"; then
            printf "${YELLOW}$NODE is not serving certificate signed for $newLoadBalancerHost${NC}\n"
        fi
    done
}

function ekco_handle_load_balancer_address_change_post_init() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 0
    fi

    splitHostPort $1
    local oldLoadBalancerHost=$HOST
    splitHostPort $2
    local newLoadBalancerHost=$HOST

    if [ "$oldLoadBalancerHost" = "$newLoadBalancerHost" ]; then
        return 0
    fi

    local ARG=--drop-alt-names=$oldLoadBalancerHost

    for NODE in "${KUBERNETES_REMOTE_PRIMARIES[@]}"; do
        logStep "Removing old load balancer address $oldLoadBalancerHost from API server certificate on node $NODE"
        local podName=regen-cert-$NODE
        kubectl delete pod $podName --force --grace-period=0 2>/dev/null || true
        render_yaml_file "$DIR/addons/ekco/$EKCO_VERSION/regen-cert-pod.yaml" | kubectl apply -f -
        spinner_until 120 kubernetes_pod_started $podName default
        kubectl logs -f $podName
        spinner_until 10 kubernetes_pod_completed $podName default
        local phase=$(kubectl get pod $podName -ojsonpath='{ .status.phase }')
        if [ "$phase" != "Succeeded" ]; then
            bail "Pod $podName phase: $phase"
        fi
        kubectl delete pod $podName --force --grace-period=0
    done
}

# The internal load balancer is a static pod running haproxy on every node. When joining, kubeadm
# needs to connect to the Kubernetes API before starting kubelet. To workaround this problem,
# temporarily run haproxy as a container directly with docker or containerd.
function ekco_bootstrap_internal_lb() {
    local backends="$PRIMARY_HOST"
    if [ -z "$backends" ] && [ "$MASTER" = "1" ]; then
        backends="$PRIVATE_ADDRESS"
    fi

    # Check if load balancer is already bootstrapped before we update the manifests
    # which will cause the load balancer to restart.
    local already_bootstrapped=0
    local last_modified=
    if curl -skf https://localhost:6444/healthz >/dev/null && [ -f /etc/kubernetes/manifests/haproxy.yaml ] ; then
        already_bootstrapped=1
        last_modified="$(stat -c %Y /etc/kubernetes/manifests/haproxy.yaml)"
    fi

    logStep "Updating the Kubernetes apiserver load balancer"

    # Always regenerate the manifests to account for updates.
    # Note: this could cause downtime when kublet syncs the manifests for a new haproxy version
    if [ -n "$DOCKER_VERSION" ]; then
        mkdir -p /etc/kubernetes/manifests
        docker run --rm \
            --entrypoint="/usr/bin/ekco" \
            --volume '/etc:/host/etc' \
            "replicated/ekco:v$EKCO_VERSION" \
            generate-haproxy-manifest \
                --file=/host/etc/kubernetes/manifests/haproxy.yaml \
                --image="$EKCO_HAPROXY_IMAGE"
    else
        mkdir -p /etc/kubernetes/manifests
        if [ "$AIRGAP" != "1" ] && ! ctr -n k8s.io images ls | grep -qF "docker.io/replicated/ekco:v$EKCO_VERSION" ; then
            # the image will not be loaded from the add-on directory and thus will not exist in the dev environment
            ctr -n k8s.io images pull "docker.io/replicated/ekco:v$EKCO_VERSION" >/dev/null
        fi
        ctr -n k8s.io run --rm \
            --mount "type=bind,src=/etc,dst=/host/etc,options=rbind:rw" \
            "docker.io/replicated/ekco:v$EKCO_VERSION" \
            haproxy-manifest \
            ekco generate-haproxy-manifest \
                --file=/host/etc/kubernetes/manifests/haproxy.yaml \
                --image="$EKCO_HAPROXY_IMAGE"
    fi

    if [ "$already_bootstrapped" = "1" ]; then
        log "Waiting for the Kubernetes apiserver load balancer to restart"
        if [ "$last_modified" != "$(stat -c %Y /etc/kubernetes/manifests/haproxy.yaml)" ]; then
            sleep_spinner 60 # allow time for the kubelet to detect the manifest change
        fi
        if ! spinner_until 300 curl -skf https://localhost:6444/healthz >/dev/null ; then
            bail "Failed to restart the Kubernetes apiserver load balancer"
        fi
        return 0
    fi

    # Sanity check as nothing can be done if there are no backends
    if [ -z "$backends" ]; then
        return 0
    fi

    if [ -n "$DOCKER_VERSION" ]; then
        mkdir -p /etc/haproxy
        docker run --rm \
            --entrypoint="/usr/bin/ekco" \
            "replicated/ekco:v$EKCO_VERSION" \
            generate-haproxy-config --primary-host="$backends" \
            > /etc/haproxy/haproxy.cfg

        docker rm -f bootstrap-lb &>/dev/null || true
        docker run -d -p "6444:6444" -v /etc/haproxy:/usr/local/etc/haproxy --name bootstrap-lb "${EKCO_HAPROXY_IMAGE}"
    else
        mkdir -p /etc/haproxy
        local haproxy_image_name=
        haproxy_image_name="$(canonical_image_name "${EKCO_HAPROXY_IMAGE}")"

        # the image will not be loaded from the add-on directory and thus will not exist in the dev environment
        if [ "$AIRGAP" != "1" ]; then
            if ! ctr -n k8s.io images ls | grep -qF "docker.io/replicated/ekco:v$EKCO_VERSION" ; then
                ctr -n k8s.io images pull "docker.io/replicated/ekco:v$EKCO_VERSION" >/dev/null
            fi
            if ! ctr -n k8s.io images ls | grep -qF "$haproxy_image_name" ; then
                ctr -n k8s.io images pull "$haproxy_image_name" >/dev/null
            fi
        fi
        ctr -n k8s.io run --rm \
            "docker.io/replicated/ekco:v$EKCO_VERSION" \
            haproxy-cfg \
            ekco generate-haproxy-config --primary-host="$backends" \
            > /etc/haproxy/haproxy.cfg

        ctr -n k8s.io task kill -s SIGKILL bootstrap-lb || true
        ctr -n k8s.io containers delete bootstrap-lb || true
        ctr -n k8s.io run \
            --mount "type=bind,src=/etc/haproxy,dst=/usr/local/etc/haproxy,options=rbind:ro" \
            --net-host \
            --detach \
            "$haproxy_image_name" \
            bootstrap-lb
    fi

    # If we are overwriting the haproxy config and missing any backends, we better tell EKCO to
    # regenerate it. This code may execute before Kubernetes is installed.
    if [ "$MASTER" = "1" ] && commandExists "kubectl" ; then
        kubectl -n kurl delete --ignore-not-found configmap update-internallb &>/dev/null || true
    fi

    # Ensure we can read this directory even when there is a system wide umask policy that prohibits
    # reading the haproxy config file such as 'umask 0027'.
    # The kubelet creates a static haproxy pod which mounts haproxy.cfg as a hostpath volume. If
    # the file does not have read permission for 'others', the haproxy container will not start
    # during kubeadm init.
    if [ -f /etc/haproxy/haproxy.cfg ]; then
        chmod -R o+rX /etc/haproxy
    fi
}

function ekco_cleanup_bootstrap_internal_lb() {
    if commandExists docker; then
        docker rm -f bootstrap-lb &>/dev/null || true
    fi
    if commandExists ctr; then
        ctr --namespace k8s.io task kill -s SIGKILL bootstrap-lb &>/dev/null || true
        ctr --namespace k8s.io containers delete bootstrap-lb &>/dev/null || true
    fi
}

function ekco_handle_load_balancer_address_change_kubeconfigs() {
    # The change-load-balancer command will restart kubelet on all remote nodes after updating
    # kubeconfigs. When kubelet restarts on the node where the ekco pod is scheduled, the connection
    # to the change-load-balancer output stream will break, but the command will continue running
    # in the pod to completion. Therefore the command output has to be redirected to a file in the
    # pod and then we have to poll that file to determine when the command is finished and if it was
    # successful
    exclude=$(get_local_node_name)
    if [ "$EKCO_ENABLE_INTERNAL_LOAD_BALANCER" = "1" ]; then
        kubectl -n kurl exec deploy/ekc-operator -- /bin/bash -c "ekco change-load-balancer --exclude=${exclude} --internal --server=https://localhost:6444 &>/tmp/change-lb-log"
    else
        kubectl -n kurl exec deploy/ekc-operator -- /bin/bash -c "ekco change-load-balancer --exclude=${exclude} --server=https://${API_SERVICE_ADDRESS} &>/tmp/change-lb-log"
    fi

    log "Waiting up to 10 minutes for kubeconfigs on remote nodes to begin using new load balancer address"
    spinner_until 600 ekco_change_lb_completed

    logs=$(kubectl -n kurl exec -i deploy/ekc-operator -- cat /tmp/change-lb-log)
    if ! echo "$logs" | grep -q "Result: success"; then
        echo "$logs"
        bail "Failed to update server address in kubeconfigs on remote ndoes"
    fi
}

function ekco_change_lb_completed() {
    2>/dev/null kubectl -n kurl exec -i deploy/ekc-operator -- grep -q "Result:" /tmp/change-lb-log
}


function ekco_create_deployment() {
    local src="$1"
    local dst="$2"

    cp "$src/kustomization.yaml" "$dst/kustomization.yaml"
    cp "$src/namespace.yaml" "$dst/namespace.yaml"
    cp "$src/rbac.yaml" "$dst/rbac.yaml"
    cp "$src/rolebinding.yaml" "$dst/rolebinding.yaml"
    cp "$src/rotate-certs-rbac.yaml" "$dst/rotate-certs-rbac.yaml"

    # is rook enabled
    if kubectl get ns rook-ceph >/dev/null 2>&1 ; then
        cp "$src/rbac-rook.yaml" "$dst/rbac-rook.yaml"
        insert_resources "$dst/kustomization.yaml" rbac-rook.yaml
        cat "$src/rolebinding-rook.yaml" >> "$dst/rolebinding.yaml"

        if [ -n "$EKCO_ROOK_PRIORITY_CLASS" ]; then
            kubectl label namespace rook-ceph rook-priority.kurl.sh="" --overwrite
        fi
    fi

    if [ -n "$MINIO_VERSION" ]; then
        cp "$src/rbac-minio.yaml" "$dst/rbac-minio.yaml"
        insert_resources "$dst/kustomization.yaml" rbac-minio.yaml
        render_yaml_file_2 "$src/rolebinding-minio.yaml" >> "$dst/rolebinding.yaml"

        if ! kubectl get namespace "$MINIO_NAMESPACE" >/dev/null 2>&1 ; then
            kubectl create --save-config namespace "$MINIO_NAMESPACE"
        fi
    fi

     if [ -n "$KOTSADM_VERSION" ]; then
        cp "$src/rbac-kotsadm.yaml" "$dst/rbac-kotsadm.yaml"
        insert_resources "$dst/kustomization.yaml" rbac-kotsadm.yaml
        render_yaml_file_2 "$src/rolebinding-kotsadm.yaml" >> "$dst/rolebinding.yaml"
    fi

    local rook_storage_nodes=
    if [ -n "$ROOK_NODES" ]; then
        # replace newlines with \n and escape double quotes
        # configmap.tmpl.yaml makes use of local variable rook_storage_nodes
        # shellcheck disable=SC2034
        rook_storage_nodes="$(echo "$ROOK_NODES" | yaml_escape_string_quotes | yaml_newline_to_literal)"
    fi
    
    # configmap.tmpl.yaml makes use of the global variable EKCO_AUTH_TOKEN
    # shellcheck disable=SC2034
    EKCO_AUTH_TOKEN=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c64)
    render_yaml_file_2 "$src/configmap.tmpl.yaml" > "$dst/configmap.yaml"

    # service.tmpl.yaml makes use of the global variable EKCO_NODE_PORT
    # shellcheck disable=SC2034
    EKCO_NODE_PORT=31880
    render_yaml_file_2 "$src/service.tmpl.yaml" > "$dst/service.yaml"

    local ekco_config_hash=
    # deployment.tmpl.yaml makes use of local variable ekco_config_hash
    # shellcheck disable=SC2034
    ekco_config_hash="$(ekco_generate_config_hash "$dst")"
    render_yaml_file_2 "$src/deployment.tmpl.yaml" > "$dst/deployment.yaml"

    kubectl apply -k "$dst"
    # apply rolebindings separately so as not to override the namespace
    kubectl apply -f "$dst/rolebinding.yaml"

    # delete pod to re-read the config map
    kubectl -n kurl delete pod -l app=ekc-operator 2>/dev/null || true
}

function ekco_load_images() {
    if [ -z "$EKCO_POD_IMAGE_OVERRIDES" ] || [ "$AIRGAP" != "1" ]; then
        return 0
    fi

    logStep "Loading ekco image overrides"

    if [ -n "$DOCKER_VERSION" ]; then
        find "$DIR/image-overrides" -type f | xargs -I {} bash -c "docker load < {}"
    else
        find "$DIR/image-overrides" -type f | xargs -I {} bash -c "cat {} | ctr -a $(${K8S_DISTRO}_get_containerd_sock) -n=k8s.io images import -"
    fi

    logSuccess "ekco image overrides loaded"
}

function ekco_generate_config_hash() {
    local dst="$1"
    md5sum "$dst/configmap.yaml" | awk '{ print $1 }'
}

function ekco_dynamicstorage() {
    if [ -n "$ROOK_MINIMUM_NODE_COUNT" ] && [ "$ROOK_MINIMUM_NODE_COUNT" -gt "1" ]; then
        # check if the rook storageclass name exists - if it does we've already migrated and should not recreate/update 'scaling'
        # yes the env var for rook's storage class name is "STORAGE_CLASS" - this is not a typo
        if kubectl get storageclasses.storage.k8s.io "$STORAGE_CLASS" >/dev/null 2>&1; then
            return 0
        fi
        kubectl apply -f "$src/storageclass-scaling.yaml"
    fi
}
