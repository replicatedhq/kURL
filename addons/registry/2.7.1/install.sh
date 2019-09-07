
function registry() {
    cp "$DIR/addons/registry/2.7.1/kustomization.yaml" "$DIR/kustomize/registry/kustomization.yaml"
    cp "$DIR/addons/registry/2.7.1/namespace.yaml" "$DIR/kustomize/registry/namespace.yaml"
    cp "$DIR/addons/registry/2.7.1/deployment-pvc.yaml" "$DIR/kustomize/registry/deployment-pvc.yaml"
    cp "$DIR/addons/registry/2.7.1/service.yaml" "$DIR/kustomize/registry/service.yaml"

    registry_session_secret

    kubectl apply -k "$DIR/kustomize/registry"

    DOCKER_REGISTRY_ADDRESS=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')

    registry_cred_secrets

    registry_pki_secret

    registry_docker_ca
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

    local address="$1"
    local user=kurl
    local password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)

    docker run \
        --entrypoint htpasswd \
        registry:2.7.1 -Bbn "$user" "$password" > htpasswd
    kubectl -n kurl create secret generic registry-htpasswd --from-file=htpasswd
    rm htpasswd

    kubectl -n default create secret docker-registry registry-creds \
        --docker-server="$DOCKER_REGISTRY_ADDRESS" \
        --docker-username="$user" \
        --docker-password="$password"
}

function registry_docker_ca() {
    if [ -z "$DOCKER_REGISTRY_ADDRESS" ]; then
        bail "Docker registry address required"
    fi

    mkdir -p /etc/docker/certs.d/$DOCKER_REGISTRY_ADDRESS
    ln -s --force /etc/kubernetes/pki/ca.crt /etc/docker/certs.d/$DOCKER_REGISTRY_ADDRESS/ca.crt
}

function registry_pki_secret() {
    if kubernetes_resource_exists kurl secret registry-pki; then
        return 0
    fi

    local clusterIP="$1"

    openssl req -newkey rsa:2048 -nodes -keyout registry.key -out registry.csr -subj="/CN=$clusterIP"
    openssl x509 -req -days 365 -sha256 -in registry.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -set_serial 1 -out registry.crt

    kubectl -n kurl create secret generic registry-pki --from-file=registry.key --from-file=registry.crt

    rm registry.key registry.csr registry.crt
}
