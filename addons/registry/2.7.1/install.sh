
function registry() {
    cp "$DIR/addons/registry/2.7.1/kustomization.yaml" "$DIR/kustomize/registry/kustomization.yaml"
    cp "$DIR/addons/registry/2.7.1/namespace.yaml" "$DIR/kustomize/registry/namespace.yaml"
    cp "$DIR/addons/registry/2.7.1/deployment-pvc.yaml" "$DIR/kustomize/registry/deployment-pvc.yaml"
    cp "$DIR/addons/registry/2.7.1/service.yaml" "$DIR/kustomize/registry/service.yaml"

    registry_session_secret

    if [ -n "$REGISTRY_PUBLISH_PORT" ]; then
        render_yaml_file "$DIR/addons/registry/2.7.1/tmpl-node-port.yaml" > "$DIR/kustomize/registry/node-port.yaml" 
        insert_patches_strategic_merge "$DIR/kustomize/registry/kustomization.yaml" node-port.yaml
    fi

    kubectl apply -k "$DIR/kustomize/registry"

    DOCKER_REGISTRY_IP=$(kubectl -n kurl get service registry -o=jsonpath='{@.spec.clusterIP}')

    registry_cred_secrets

    registry_pki_secret "$DOCKER_REGISTRY_IP"

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

    local user=kurl
    local password=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)

    # if the registry pod is already running it will pick up changes to the secret without restart
    docker run --rm \
        --entrypoint htpasswd \
        registry:2.7.1 -Bbn "$user" "$password" > htpasswd
    kubectl -n kurl create secret generic registry-htpasswd --from-file=htpasswd
    rm htpasswd

    kubectl -n default create secret docker-registry registry-creds \
        --docker-server="$DOCKER_REGISTRY_IP" \
        --docker-username="$user" \
        --docker-password="$password"
}

function registry_docker_ca() {
    if [ -z "$DOCKER_REGISTRY_IP" ]; then
        bail "Docker registry address required"
    fi

    mkdir -p /etc/docker/certs.d/$DOCKER_REGISTRY_IP
    ln -s --force /etc/kubernetes/pki/ca.crt /etc/docker/certs.d/$DOCKER_REGISTRY_IP/ca.crt
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

    openssl req -newkey rsa:2048 -nodes -keyout registry.key -out registry.csr -config registry.cnf
    openssl x509 -req -days 365 -in registry.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out registry.crt -extensions v3_ext -extfile registry.cnf

    # rotate the cert and restart the pod every time
    kubectl -n kurl delete secret registry-pki &>/dev/null || true
    kubectl -n kurl create secret generic registry-pki --from-file=registry.key --from-file=registry.crt
    kubectl -n kurl delete pod -l app=registry &>/dev/null || true

    popd
    rm -r "$tmp"
}
