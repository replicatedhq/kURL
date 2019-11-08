
function kotsadm() {
    local src="$DIR/addons/kotsadm/0.9.14"
    local dst="$DIR/kustomize/kotsadm"

    rook_create_bucket kotsadm

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/api.yaml" "$dst/"
    cp "$src/operator.yaml" "$dst/"
    cp "$src/postgres.yaml" "$dst/"
    cp "$src/schemahero.yaml" "$dst/"
    cp "$src/web.yaml" "$dst/"

    kotsadm_secret_auto_create_cluster_token
    kotsadm_secret_password
    kotsadm_secret_postgres
    kotsadm_secret_s3
    kotsadm_secret_session
    if [ -n "$PROMETHEUS_VERSION" ]; then
        kotsadm_api_patch_prometheus
    fi

    kotsadm_etcd_client_secret

    if [ "$AIRGAP" != "1" ]; then
        curl $REPLICATED_APP_URL/metadata/$KOTSADM_APPLICATION_SLUG > "$src/application.yaml"
    fi
    cp "$src/application.yaml" "$dst/"
    kubectl create configmap kotsadm-application-metadata --from-file="$dst/application.yaml" --dry-run -oyaml > "$dst/kotsadm-application-metadata.yaml"

    if [ -z "$KOTSADM_HOSTNAME" ]; then
        KOTSADM_HOSTNAME="$PUBLIC_ADDRESS"
    fi
    if [ -z "$KOTSADM_HOSTNAME" ]; then
        KOTSADM_HOSTNAME="$PRIVATE_ADDRESS"
    fi
    cat "$src/tmpl-start-kotsadm-web.sh" | sed "s/###_HOSTNAME_###/$KOTSADM_HOSTNAME:8800/g" > "$dst/start-kotsadm-web.sh"
    kubectl create configmap kotsadm-web-scripts --from-file="$dst/start-kotsadm-web.sh" --dry-run -oyaml > "$dst/kotsadm-web-scripts.yaml"

    kubectl delete pod kotsadm-migrations || true;

    kubectl apply -k "$dst/"

    kotsadm_kurl_proxy $src $dst
}

function kotsadm_outro() {
    local apiPod=$(kubectl get pods --selector app=kotsadm-api --no-headers | grep -E '(ContainerCreating|Running)' | head -1 | awk '{ print $1 }')
    if [ -z "$apiPod" ]; then
        apiPod="<api-pod>"
    fi
    local webPod=$(kubectl get pods --selector app=kotsadm-web --no-headers | grep -E '(ContainerCreating|Running)' | head -1 | awk '{ print $1 }')
    if [ -z "$webPod" ]; then
        webPod="<web-pod>"
    fi

    printf "\n"
    printf "\n"
    printf "Kotsadm: ${GREEN}http://$KOTSADM_HOSTNAME:8800${NC}\n"

    if [ -n "$KOTSADM_PASSWORD" ]; then
        printf "Login with password (will not be shown again): ${GREEN}$KOTSADM_PASSWORD${NC}\n"
    else
        printf "Password not regenerated. Delete the kotsadm-password secret and re-run installer to force re-generation.\n"
    fi
    printf "\n"
    printf "\n"
}

function kotsadm_secret_auto_create_cluster_token() {
    local AUTO_CREATE_CLUSTER_TOKEN=$(kubernetes_secret_value default kotsadm-auto-create-cluster-token token)

    if [ -n "$AUTO_CREATE_CLUSTER_TOKEN" ]; then
        return 0
    fi

    AUTO_CREATE_CLUSTER_TOKEN=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)

    render_yaml_file "$DIR/addons/kotsadm/0.9.14/tmpl-secret-auto-create-cluster-token.yaml" > "$DIR/kustomize/kotsadm/secret-auto-create-cluster-token.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-auto-create-cluster-token.yaml

    # ensure all pods that consume the secret will be restarted
    kubernetes_scale_down default deployment kotsadm-api
    kubernetes_scale_down default deployment kotsadm-operator
}

function kotsadm_secret_password() {
    local BCRYPT_PASSWORD=$(kubernetes_secret_value default kotsadm-password passwordBcrypt)

    if [ -n "$BCRYPT_PASSWORD" ]; then
        return 0
    fi

    # global, used in outro
    KOTSADM_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c9)
    # TODO kurl-util
    BCRYPT_PASSWORD=$(docker run --rm epicsoft/bcrypt:latest hash "$KOTSADM_PASSWORD" 14)

    render_yaml_file "$DIR/addons/kotsadm/0.9.14/tmpl-secret-password.yaml" > "$DIR/kustomize/kotsadm/secret-password.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-password.yaml

    kubernetes_scale_down default deployment kotsadm-api
}

function kotsadm_secret_postgres() {
    local POSTGRES_PASSWORD=$(kubernetes_secret_value default kotsadm-postgres password)

    if [ -n "$POSTGRES_PASSWORD" ]; then
        return 0
    fi

    POSTGRES_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)

    render_yaml_file "$DIR/addons/kotsadm/0.9.14/tmpl-secret-postgres.yaml" > "$DIR/kustomize/kotsadm/secret-postgres.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-postgres.yaml

    kubernetes_scale_down default deployment kotsadm-api
    kubernetes_scale_down default deployment kotsadm-postgres
    kubernetes_scale_down default deployment kotsadm-migrations
}

function kotsadm_secret_s3() {
    render_yaml_file "$DIR/addons/kotsadm/0.9.14/tmpl-secret-s3.yaml" > "$DIR/kustomize/kotsadm/secret-s3.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-s3.yaml
}

function kotsadm_secret_session() {
    local JWT_SECRET=$(kubernetes_secret_value default kotsadm-session key)

    if [ -n "$JWT_SECRET" ]; then
        return 0
    fi

    JWT_SECRET=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)

    render_yaml_file "$DIR/addons/kotsadm/0.9.14/tmpl-secret-session.yaml" > "$DIR/kustomize/kotsadm/secret-session.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-session.yaml

    kubernetes_scale_down default deployment kotsadm-api
}

function kotsadm_api_patch_prometheus() {
    insert_patches_strategic_merge "$DIR/kustomize/kotsadm/kustomization.yaml" api-prometheus.yaml
    cp "$DIR/addons/kotsadm/0.9.14/patches/api-prometheus.yaml" "$DIR/kustomize/kotsadm/api-prometheus.yaml"
}

function kotsadm_kurl_proxy() {
    local src="$1/kurl-proxy"
    local dst="$2/kurl-proxy"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/rbac.yaml" "$dst/"

    render_yaml_file "$src/tmpl-service.yaml" > "$dst/service.yaml"
    render_yaml_file "$src/tmpl-deployment.yaml" > "$dst/deployment.yaml"

    kotsadm_tls_secret

    kubectl apply -k "$dst/"
}

# TODO rotate without overwriting uploaded certs
function kotsadm_tls_secret() {
    if kubernetes_resource_exists default secret kotsadm-tls; then
        return 0
    fi

    cat > kotsadm.cnf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
CN = kotsadm-web.default.svc.cluster.local

[ req_ext ]
subjectAltName = @alt_names

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=nonRepudiation,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names

[ alt_names ]
DNS.1 = kotsadm-web
DNS.2 = kotsadm-web.default
DNS.3 = kotsadm-web.default.svc
DNS.4 = kotsadm-web.default.svc.cluster
DNS.5 = kotsadm-web.default.svc.cluster.local
IP.1 = $PRIVATE_ADDRESS
EOF
    if [ -n "$PUBLIC_ADDRESS" ]; then
        echo "IP.2 = $PUBLIC_ADDRESS" >> kotsadm.cnf
    fi

    openssl req -newkey rsa:2048 -nodes -keyout kotsadm.key -config kotsadm.cnf -x509 -days 365 -out kotsadm.crt

    kubectl -n default create secret generic kotsadm-tls --from-file=tls.key=kotsadm.key --from-file=tls.crt=kotsadm.crt --from-literal=acceptAnonymousUploads=1

    rm kotsadm.cnf kotsadm.key kotsadm.crt
}

# TODO rotate
function kotsadm_etcd_client_secret() {
    if kubernetes_resource_exists default secret etcd-client-cert; then
        return 0
    fi

    kubectl -n default create secret generic etcd-client-cert \
        --from-file=client.crt=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
        --from-file=client.key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
        --from-file=/etc/kubernetes/pki/etcd/ca.crt
}
