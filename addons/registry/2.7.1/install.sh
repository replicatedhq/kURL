
function registry() {
    cp "$DIR/addons/registry/2.7.1/kustomization.yaml" "$DIR/kustomize/registry/kustomization.yaml"
    cp "$DIR/addons/registry/2.7.1/service.yaml" "$DIR/kustomize/registry/service.yaml"

    registry_session_secret

    # Only create registry deployment with object store if rook or minio exists and the registry pvc
    # doesn't already exist.
    if ! registry_pvc_exists && object_store_exists; then
        registry_object_store_bucket
        render_yaml_file "$DIR/addons/registry/2.7.1/tmpl-deployment-objectstore.yaml" > "$DIR/kustomize/registry/deployment-objectstore.yaml"
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" deployment-objectstore.yaml
    else
        cp "$DIR/addons/registry/2.7.1/deployment-pvc.yaml" "$DIR/kustomize/registry/deployment-pvc.yaml"
        insert_resources "$DIR/kustomize/registry/kustomization.yaml" deployment-pvc.yaml
    fi

    kubectl apply -k "$DIR/kustomize/registry"

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')

    registry_cred_secrets

    registry_pki_secret "$DOCKER_REGISTRY_IP"

    registry_docker_ca
}

function registry_pre_init() {
    if [ -n "$KURL_REGISTRY_IP" ]; then
        DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")
        if [ -n "$DOCKER_REGISTRY_IP" ] && [ "$DOCKER_REGISTRY_IP" != "$KURL_REGISTRY_IP" ]; then
            bail "kurl-registry-ip is specified, however registry service is already assigned $DOCKER_REGISTRY_IP"
        fi
    fi
}

function create_registry_service() {
    mkdir -p "$DIR/kustomize/registry"
    cp "$DIR/addons/registry/2.7.1/kustomization.yaml" "$DIR/kustomize/registry/kustomization.yaml"
    cp "$DIR/addons/registry/2.7.1/service.yaml" "$DIR/kustomize/registry/service.yaml"

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || echo "")
    if [ -n "$DOCKER_REGISTRY_IP" ] && [ -z "$KURL_REGISTRY_IP" ]; then
        KURL_REGISTRY_IP=$DOCKER_REGISTRY_IP
    fi

    if [ -n "$REGISTRY_PUBLISH_PORT" ]; then
        render_yaml_file "$DIR/addons/registry/2.7.1/tmpl-node-port.yaml" > "$DIR/kustomize/registry/service.yaml"
    else
        render_yaml_file "$DIR/addons/registry/2.7.1/tmpl-cluster-ip.yaml" > "$DIR/kustomize/registry/service.yaml"
    fi
    insert_resources "$DIR/kustomize/registry/kustomization.yaml" service.yaml
    kubectl apply -k "$DIR/kustomize/registry"
}

function registry_join() {
    registry_docker_ca
}

function registry_session_secret() {
    if kubernetes_resource_exists kurl secret registry-session-secret; then
        return 0
    fi

    insert_resources "$DIR/kustomize/registry/kustomization.yaml" secret.yaml

    local HA_SHARED_SECRET=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    render_yaml_file "$DIR/addons/registry/2.7.1/tmpl-secret.yaml" > "$DIR/kustomize/registry/secret.yaml"
}

# Create the registry-htpasswd secret in the kurl namespace for the registry to use for
# authentication and the registry-credentials secret in the default namespace for pods to use for
# image pulls
function registry_cred_secrets() {
    if kubernetes_resource_exists kurl secret registry-htpasswd && kubernetes_resource_exists default secret registry-creds ; then
        return 0
    fi
    kubectl -n kurl delete secret registry-htpasswd &>/dev/null || true
    kubectl -n default delete secret registry-creds &>/dev/null || true

    local user=kurl
    local password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)

    # if the registry pod is already running it will pick up changes to the secret without restart
    BIN_HTPASSWD=./bin/htpasswd
    $BIN_HTPASSWD -u "$user" -p "$password" -f htpasswd
    kubectl -n kurl create secret generic registry-htpasswd --from-file=htpasswd
    kubectl -n kurl patch secret registry-htpasswd -p '{"metadata":{"labels":{"kots.io/kotsadm":"true", "kots.io/backup":"velero"}}}'
    rm htpasswd

    kubectl -n default create secret docker-registry registry-creds \
        --docker-server="$DOCKER_REGISTRY_IP" \
        --docker-username="$user" \
        --docker-password="$password"
    kubectl -n default patch secret registry-creds -p '{"metadata":{"labels":{"kots.io/kotsadm":"true", "kots.io/backup":"velero"}}}'
}

function registry_docker_ca() {
    if [ -z "$DOCKER_REGISTRY_IP" ]; then
        bail "Docker registry address required"
    fi

    if [ -n "$DOCKER_VERSION" ]; then
        local ca_crt="$(${K8S_DISTRO}_get_server_ca)"

        mkdir -p /etc/docker/certs.d/$DOCKER_REGISTRY_IP
        ln -s --force "${ca_crt}" /etc/docker/certs.d/$DOCKER_REGISTRY_IP/ca.crt
    fi
}

function registry_containerd_init() {
    if [ -z "$REGISTRY_VERSION" ]; then
        return 0
    fi

    local registry_ip=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}' 2>/dev/null || true)
    if [ -z "$registry_ip" ]; then
        kubectl -n kurl create service clusterip registry --tcp=443:443
        registry_ip=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')
    fi

    registry_containerd_configure "$registry_ip"
    ${K8S_DISTRO}_containerd_restart
}

REGISTRY_CONTAINERD_CA_ADDED=0
function registry_containerd_configure() {
    local registry_ip="$1"
    ${K8S_DISTRO}_registry_containerd_configure "${registry_ip}"

    if grep -q "plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"${registry_ip}\".tls" /etc/containerd/config.toml; then
        echo "Registry ${registry_ip} TLS already configured for containerd"
        return 0
    fi

    cat >> /etc/containerd/config.toml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.configs."${registry_ip}".tls]
  ca_file = "/etc/kubernetes/pki/ca.crt"
EOF

    REGISTRY_CONTAINERD_CA_ADDED=1
}

function registry_pki_secret() {
    if [ -z "$DOCKER_REGISTRY_IP" ]; then
        bail "Docker registry address required"
    fi

    local tmp="$DIR/addons/registry/2.7.1/tmp"
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
        echo "IP.2 = $PRIVATE_ADDRESS" >> registry.cnf

        if [ -n "$PUBLIC_ADDRESS" ]; then
            echo "IP.3 = $PUBLIC_ADDRESS" >> registry.cnf
        fi
    fi

    local ca_crt="$(${K8S_DISTRO}_get_server_ca)"
    local ca_key="$(${K8S_DISTRO}_get_server_ca_key)"

    openssl req -newkey rsa:2048 -nodes -keyout registry.key -out registry.csr -config registry.cnf
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
