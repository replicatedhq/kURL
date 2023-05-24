# shellcheck disable=SC2148
function registry() {

    registry_install

    kubectl apply -k "$DIR/kustomize/registry"

    if registry_is_pvc_migrating; then
        logWarn "Registry will migrate from object store to pvc"
        try_5m registry_pvc_migrated
        logSuccess "Registry migration complete"
    fi

    logSubstep "Configuring Registry"
    registry_cred_secrets
    registry_pki_secret "$DOCKER_REGISTRY_IP"
    registry_docker_ca
    logSuccess "Registry configured successfully"

    registry_healthy
}

function registry_install() {
    logSubstep "Installing Registry"
    regsitry_init_service   # need this again because kustomize folder is cleaned before install
    registry_session_secret

    # Only create registry deployment with object store if rook or minio exists IN THE INSTALLER SPEC and the registry pvc
    # doesn't already exist.
    log "Checking if PVC and Object Store exists"
    if ! registry_pvc_exists && object_store_exists; then
        log "PVC and Object Store were found. Creating Registry Deployment with Object Store data"
        registry_object_store_bucket
        # shellcheck disable=SC2034  # used in the deployment template
        objectStoreIP=$($DIR/bin/kurl format-address $OBJECT_STORE_CLUSTER_IP)
        objectStoreHostname=$(echo $OBJECT_STORE_CLUSTER_HOST | sed 's/http:\/\///')
        log "Object Store IP: $objectStoreIP"
        log "Object Store Hostname: $objectStoreHostname"
        render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-deployment-objectstore.yaml" > "$DIR/kustomize/registry/deployment-objectstore.yaml"
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" deployment-objectstore.yaml

        cp "$DIR/addons/registry/2.8.2/patch-deployment-velero.yaml" "$DIR/kustomize/registry/patch-deployment-velero.yaml"
        insert_patches_strategic_merge "$DIR/kustomize/registry/kustomization.yaml" patch-deployment-velero.yaml
        render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-configmap-velero.yaml" > "$DIR/kustomize/registry/configmap-velero.yaml"
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" configmap-velero.yaml
    else
        log "PVC and Object Store were NOT found. Creating Registry Deployment"
        determine_registry_pvc_size
        cp "$DIR/addons/registry/2.8.2/deployment-pvc.yaml" "$DIR/kustomize/registry/deployment-pvc.yaml"
        render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-persistentvolumeclaim.yaml" > "$DIR/kustomize/registry/persistentvolumeclaim.yaml"
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" deployment-pvc.yaml
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" persistentvolumeclaim.yaml
    fi

    log "Checking if PVC migration will be required"
    if registry_will_migrate_pvc; then
        logWarn "Registry migration in progres......"

        # Object store credentials already live in the previously created secret 
        render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-configmap-migrate-s3.yaml" > "$DIR/kustomize/registry/configmap-migrate-s3.yaml"
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" configmap-migrate-s3.yaml
        cp "$DIR/addons/registry/2.8.2/patch-deployment-migrate-s3.yaml" "$DIR/kustomize/registry/patch-deployment-migrate-s3.yaml"
        insert_patches_strategic_merge "$DIR/kustomize/registry/kustomization.yaml" patch-deployment-migrate-s3.yaml
    fi
    logSuccess "Registry installed successfully"
}

# The regsitry will migrate from object store to pvc is there isn't already a PVC, the object store was remove from the installer, BUT
# it is still detected as running in the cluster. The latter 2 conditions happen during a CSI migration.
function registry_will_migrate_pvc() {
    # If KOTSADM_DISABLE_S3 is not set, don't allow the migration
    if [ "$KOTSADM_DISABLE_S3" != 1 ]; then 
        return 1
    fi
    if ! registry_pvc_exists && ! object_store_exists && object_store_running ; then
        return 0
    fi
    return 1
}

# When re-running the installer, make sure that you can perform a migration
# even when an existing install of the same addon version is detected (and `registry()` is NOT called in this case).
# Implements hook [addon]_already_applied()
function registry_already_applied() {

    if registry_will_migrate_pvc; then
        registry_install

        kubectl apply -k "$DIR/kustomize/registry"

        logWarn "Registry will migrate from object store to pvc"
        try_5m registry_pvc_migrated
        logSuccess "Registry migration complete"
    fi
}

function registry_pre_init() {
    if [ -n "$KURL_REGISTRY_IP" ]; then
        DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")
        if [ -n "$DOCKER_REGISTRY_IP" ] && [ "$DOCKER_REGISTRY_IP" != "$KURL_REGISTRY_IP" ]; then
            bail "kurl-registry-ip is specified, however registry service is already assigned $DOCKER_REGISTRY_IP"
        fi
    fi
}

function registry_init() {

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")
  
    regsitry_init_service

    kubectl apply -k "$DIR/kustomize/registry"

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')
}

function regsitry_init_service() {
    log "Applying resources"
    mkdir -p "$DIR/kustomize/registry"
    cp "$DIR/addons/registry/2.8.2/kustomization.yaml" "$DIR/kustomize/registry/kustomization.yaml"
    
    cp "$DIR/addons/registry/2.8.2/service.yaml" "$DIR/kustomize/registry/service.yaml"
    insert_resources "$DIR/kustomize/registry/kustomization.yaml" service.yaml

    if [ -n "$DOCKER_REGISTRY_IP" ] && [ -z "$KURL_REGISTRY_IP" ]; then
        KURL_REGISTRY_IP=$DOCKER_REGISTRY_IP
    fi

    if [ -n "$REGISTRY_PUBLISH_PORT" ]; then
        render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-node-port-patch.yaml" > "$DIR/kustomize/registry/node-port-patch.yaml"
        insert_patches_strategic_merge "$DIR/kustomize/registry/kustomization.yaml" "node-port-patch.yaml"
    fi

    if [ -n "$KURL_REGISTRY_IP" ]; then
        render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-cluster-ip-patch.yaml" > "$DIR/kustomize/registry/cluster-ip-patch.yaml"
        insert_patches_strategic_merge "$DIR/kustomize/registry/kustomization.yaml" "cluster-ip-patch.yaml"
    fi
}

function registry_join() {
    registry_docker_ca
}

function registry_session_secret() {
    log "Adding secret"
    if kubernetes_resource_exists kurl secret registry-session-secret; then
        return 0
    fi

    insert_resources "$DIR/kustomize/registry/kustomization.yaml" secret.yaml

    local HA_SHARED_SECRET=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    render_yaml_file "$DIR/addons/registry/2.8.2/tmpl-secret.yaml" > "$DIR/kustomize/registry/secret.yaml"
}

# Create the registry-htpasswd secret in the kurl namespace for the registry to use for
# authentication and the registry-credentials secret in the default namespace for pods to use for
# image pulls
function registry_cred_secrets() {
    log "Checking if secrets exist"
    if kubernetes_resource_exists kurl secret registry-htpasswd && kubernetes_resource_exists default secret registry-creds ; then
        log "Secrets found. Patching kotsadm labels"
        kubectl -n kurl patch secret registry-htpasswd -p '{"metadata":{"labels":{"kots.io/kotsadm":"true", "kots.io/backup":"velero"}}}'
        kubectl -n default patch secret registry-creds -p '{"metadata":{"labels":{"kots.io/kotsadm":"true", "kots.io/backup":"velero"}}}'
        return 0
    fi

    log "Deleting registry-htpasswd and registry-creds secrets"
    kubectl -n kurl delete secret registry-htpasswd &>/dev/null || true
    kubectl -n default delete secret registry-creds &>/dev/null || true

    log "Generating password"
    local user=kurl
    local password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)

    # if the registry pod is already running it will pick up changes to the secret without restart
    BIN_HTPASSWD=./bin/htpasswd
    $BIN_HTPASSWD -u "$user" -p "$password" -f htpasswd

    log "Patching password"
    kubectl -n kurl create secret generic registry-htpasswd --from-file=htpasswd
    kubectl -n kurl patch secret registry-htpasswd -p '{"metadata":{"labels":{"kots.io/kotsadm":"true", "kots.io/backup":"velero"}}}'
    rm htpasswd

    local server="$DOCKER_REGISTRY_IP"
    if [ "$IPV6_ONLY" = "1" ]; then
        log "IPV6 is in usage"
        server="registry.kurl.svc.cluster.local"
    fi

    kubectl -n default create secret docker-registry registry-creds \
        --docker-server="$server" \
        --docker-username="$user" \
        --docker-password="$password"
    kubectl -n default patch secret registry-creds -p '{"metadata":{"labels":{"kots.io/kotsadm":"true", "kots.io/backup":"velero"}}}'

    log "Secrets configured successfully"
}

function registry_docker_ca() {
    if [ -z "$DOCKER_REGISTRY_IP" ]; then
        bail "Docker registry address required"
    fi

    if [ -n "$DOCKER_VERSION" ]; then
        log "Gathering CA from server to configure Docker"
        local ca_crt="$(${K8S_DISTRO}_get_server_ca)"

        mkdir -p /etc/docker/certs.d/$DOCKER_REGISTRY_IP
        ln -s --force "${ca_crt}" /etc/docker/certs.d/$DOCKER_REGISTRY_IP/ca.crt
    fi
}

function registry_pki_secret() {
    log "Checking Docker Registry: $DOCKER_REGISTRY_IP"
    if [ -z "$DOCKER_REGISTRY_IP" ]; then
        bail "Docker registry address required"
    fi

    local tmp="$DIR/addons/registry/2.8.2/tmp"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    pushd "$tmp"

    cat > registry.cnf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
CN = registry.kurl.svc.cluster.local

[ req_ext ]
subjectAltName = @alt_names

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=nonRepudiation,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names

[ alt_names ]
DNS.1 = registry
DNS.2 = registry.kurl
DNS.3 = registry.kurl.svc
DNS.4 = registry.kurl.svc.cluster
DNS.5 = registry.kurl.svc.cluster.local
IP.1 = $DOCKER_REGISTRY_IP
EOF

    if [ -n "$REGISTRY_PUBLISH_PORT" ]; then
        log "Publish Registry Port: $REGISTRY_PUBLISH_PORT"
        echo "IP.2 = $PRIVATE_ADDRESS" >> registry.cnf

        if [ -n "$PUBLIC_ADDRESS" ]; then
            log "Publish Address: $PUBLIC_ADDRESS"
            echo "IP.3 = $PUBLIC_ADDRESS" >> registry.cnf
        fi
    fi

    log "Gathering CA from server"
    local ca_crt="$(${K8S_DISTRO}_get_server_ca)"
    local ca_key="$(${K8S_DISTRO}_get_server_ca_key)"

    log "Generating a private key and a corresponding Certificate Signing Request (CSR) using OpenSSL"
    openssl req -newkey rsa:2048 -nodes -keyout registry.key -out registry.csr -config registry.cnf

    log "Generating a self-signed X.509 certificate using OpenSSL"
    openssl x509 -req -days 365 -in registry.csr -CA "${ca_crt}" -CAkey "${ca_key}" -CAcreateserial -out registry.crt -extensions v3_ext -extfile registry.cnf

    # rotate the cert and restart the pod every time
    kubectl -n kurl delete secret registry-pki &>/dev/null || true
    kubectl -n kurl create secret generic registry-pki --from-file=registry.key --from-file=registry.crt
    kubectl -n kurl delete pod -l app=registry &>/dev/null || true

    popd
    rm -r "$tmp"
}

function registry_object_store_bucket() {
    try_1m object_store_create_bucket "docker-registry"
}

function registry_pvc_exists() {
    kubectl -n kurl get pvc registry-pvc &>/dev/null
}

# if the PVC size has already been set we should not reduce it
function determine_registry_pvc_size() {
    local registry_pvc_size="50Gi"
    if registry_pvc_exists; then
        registry_pvc_size=$( kubectl get pvc -n kurl registry-pvc -o jsonpath='{.spec.resources.requests.storage}')
    fi
    log "PVC size used is $registry_pvc_size"
    export REGISTRY_PVC_SIZE=$registry_pvc_size
}

function registry_is_pvc_migrating() {
    registry_pod=$( kubectl get pods -n kurl -l app=registry -o jsonpath='{.items[0].metadata.name}')
    kubectl -n kurl logs $registry_pod -c migrate-s3 &>/dev/null
}

function registry_pvc_migrated() {
    registry_pod=$( kubectl get pods -n kurl -l app=registry -o jsonpath='{.items[0].metadata.name}')
    if kubectl -n kurl logs $registry_pod -c migrate-s3  | grep -q "migration ran successfully" &>/dev/null; then
        return 0
    fi
    if kubectl -n kurl logs $registry_pod -c migrate-s3  | grep -q "migration has already run" &>/dev/null; then
        return 0
    fi
    return 1
}

function registry_healthy() {
    logSubstep "Checking if registry is healthy"
    echo "waiting for the registry to start"
    spinner_until 120 deployment_fully_updated kurl registry
    logSuccess "Registry is healthy"
}
