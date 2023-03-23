#!/usr/bin/env bash

EKCO_HAPROXY_IMAGE=haproxy:2.6.6-alpine3.16

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
}

function ekco() {
    local src="$DIR/addons/ekco/$EKCO_VERSION"
    local dst="$DIR/kustomize/ekco"

    ekco_create_deployment "$src" "$dst"

    if [ "$EKCO_SHOULD_INSTALL_REBOOT_SERVICE" = "1" ]; then
        ekco_install_reboot_service "$src"
    fi

    ekco_install_purge_node_command "$src"

    # Wait for the pod image override mutating webhook to be created so when other add-ons are
    # installed they will get their overridden image
    if [ -n "$EKCO_POD_IMAGE_OVERRIDES" ]; then
        ekco_load_images
        echo "Waiting up to 5 minutes for pod-image-overrides mutating webhook config to be created"
        if ! spinner_until 300 kubernetes_resource_exists kurl mutatingwebhookconfigurations pod-image-overrides.kurl.sh; then
            bail "EKCO failed to deploy the pod-image-overrides.kurl.sh mutating webhook configuration"
        fi
    fi
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
    DID_MIGRATE_ROOK_PVCS=$(kubectl -n kurl get configmap kurl-migration-from-rook -o jsonpath='{ .data.DID_MIGRATE_ROOK_PVCS }')
    if [ "$DID_MIGRATE_ROOK_PVCS" == "1" ]; then
        ekco_create_deployment "$src" "$dst"
    fi

    # check if EKCO deployment needs to be scaled up after a Rook upgrade
    maybe_scaleup_ekco_operator
}

function maybe_scaleup_ekco_operator() {
    local ekcoReplicas=
    ekcoReplicas=$(kubectl -n kurl get deployment ekc-operator -o jsonpath='{.spec.replicas}')

    if [ -z "$ekcoReplicas" ] || [ "$ekcoReplicas" -eq 0 ]; then
        echo "Scaling up EKCO operator deployment"
        kubectl -n kurl scale deploy ekc-operator --replicas=1
    fi
}

function ekco_install_reboot_service() {
    local src="$1"

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
    systemctl start ekco-reboot.service
}

function ekco_install_purge_node_command() {
    local src="$1"

    cp "$src/ekco-purge-node.sh" /usr/local/bin/ekco-purge-node
    chmod u+x /usr/local/bin/ekco-purge-node
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
        echo "Adding new load balancer $newLoadBalancerHost to API server certificate on node $NODE"
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
        echo "Waiting for $NODE to begin serving certificate signed for $newLoadBalancerHost"
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
        echo "Removing old load balancer address $oldLoadBalancerHost from API server certificate on node $NODE"
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
    if curl -skf https://localhost:6444/healthz >/dev/null ; then
        already_bootstrapped=1
        last_modified="$(stat -c %Y /etc/kubernetes/manifests/haproxy.yaml)"
    fi

    echo "Updating the Kubernetes apiserver load balancer"

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
        echo "Waiting for the Kubernetes apiserver load balancer to restart"
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

        ctr -n k8s.io task kill -s SIGKILL bootstrap-lb &>/dev/null || true
        ctr -n k8s.io containers delete bootstrap-lb &>/dev/null || true
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
    exclude=$(hostname | tr '[:upper:]' '[:lower:]')
    if [ "$EKCO_ENABLE_INTERNAL_LOAD_BALANCER" = "1" ]; then
        kubectl -n kurl exec deploy/ekc-operator -- /bin/bash -c "ekco change-load-balancer --exclude=${exclude} --internal --server=https://localhost:6444 &>/tmp/change-lb-log"
    else
        kubectl -n kurl exec deploy/ekc-operator -- /bin/bash -c "ekco change-load-balancer --exclude=${exclude} --server=https://${API_SERVICE_ADDRESS} &>/tmp/change-lb-log"
    fi

    echo "Waiting up to 10 minutes for kubeconfigs on remote nodes to begin using new load balancer address"
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
    cp "$src/kustomization.yaml" "$dst/kustomization.yaml"
    cp "$src/namespace.yaml" "$dst/namespace.yaml"
    cp "$src/rbac.yaml" "$dst/rbac.yaml"
    cp "$src/rolebinding.yaml" "$dst/rolebinding.yaml"
    cp "$src/deployment.yaml" "$dst/deployment.yaml"
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

    render_yaml_file "$src/tmpl-configmap.yaml" > "$dst/configmap.yaml"
    insert_resources "$dst/kustomization.yaml" configmap.yaml

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

    if [ -n "$DOCKER_VERSION" ]; then
        find "$DIR/image-overrides" -type f | xargs -I {} bash -c "docker load < {}"
    else
        find "$DIR/image-overrides" -type f | xargs -I {} bash -c "cat {} | ctr -a $(${K8S_DISTRO}_get_containerd_sock) -n=k8s.io images import -"
    fi
}
