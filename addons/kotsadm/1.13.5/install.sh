
function kotsadm() {
    local src="$DIR/addons/kotsadm/1.13.5"
    local dst="$DIR/kustomize/kotsadm"

    try_1m object_store_create_bucket kotsadm
    kotsadm_rename_postgres_pvc_1-12-2 "$src"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/api.yaml" "$dst/"
    cp "$src/operator.yaml" "$dst/"
    cp "$src/postgres.yaml" "$dst/"
    cp "$src/schemahero.yaml" "$dst/"
    cp "$src/kotsadm.yaml" "$dst/"

    kotsadm_secret_cluster_token
    kotsadm_secret_password
    kotsadm_secret_postgres
    kotsadm_secret_s3
    kotsadm_secret_session
    kotsadm_api_encryption_key
    if [ -n "$PROMETHEUS_VERSION" ]; then
        kotsadm_api_patch_prometheus
    fi

    kotsadm_etcd_client_secret
    kotsadm_kubelet_client_secret

    kotsadm_metadata_configmap $src $dst

    if [ -z "$KOTSADM_HOSTNAME" ]; then
        KOTSADM_HOSTNAME="$PUBLIC_ADDRESS"
    fi
    if [ -z "$KOTSADM_HOSTNAME" ]; then
        KOTSADM_HOSTNAME="$PRIVATE_ADDRESS"
    fi

    cat "$src/tmpl-start-kotsadm-web.sh" | sed "s/###_HOSTNAME_###/$KOTSADM_HOSTNAME:8800/g" > "$dst/start-kotsadm-web.sh"
    kubectl create configmap kotsadm-web-scripts --from-file="$dst/start-kotsadm-web.sh" --dry-run -oyaml > "$dst/kotsadm-web-scripts.yaml"

    kubectl delete pod kotsadm-migrations || true;
    kubectl delete deployment kotsadm-web || true; # replaced by 'kotsadm' deployment in 1.12.0
    kubectl delete service kotsadm-api || true; # replaced by 'kotsadm-api-node' service in 1.12.0

    kotsadm_namespaces "$src" "$dst"

    kubectl apply -k "$dst/"

    kotsadm_kurl_proxy $src $dst

    kotsadm_cli $src
}

function kotsadm_join() {
    kotsadm_cli "$DIR/addons/kotsadm/1.13.5"
}

function kotsadm_outro() {
    local apiPod=$(kubectl get pods --selector app=kotsadm-api --no-headers | grep -E '(ContainerCreating|Running)' | head -1 | awk '{ print $1 }')
    if [ -z "$apiPod" ]; then
        apiPod="<api-pod>"
    fi
    local mainPod=$(kubectl get pods --selector app=kotsadm --no-headers | grep -E '(ContainerCreating|Running)' | head -1 | awk '{ print $1 }')
    if [ -z "$mainPod" ]; then
        mainPod="<main-pod>"
    fi

    printf "\n"
    printf "\n"
    printf "Kotsadm: ${GREEN}http://$KOTSADM_HOSTNAME:8800${NC}\n"

    if [ -n "$KOTSADM_PASSWORD" ]; then
        printf "Login with password (will not be shown again): ${GREEN}$KOTSADM_PASSWORD${NC}\n"
    else
        printf "Password not regenerated. Run ${GREEN}kubectl kots reset-password default${NC} to reset it\n"
    fi
    printf "\n"
    printf "\n"
}

function kotsadm_secret_cluster_token() {
    local CLUSTER_TOKEN=$(kubernetes_secret_value default kotsadm-cluster-token kotsadm-cluster-token)

    if [ -n "$CLUSTER_TOKEN" ]; then
        return 0
    fi

    # check under old name
    CLUSTER_TOKEN=$(kubernetes_secret_value default kotsadm-auto-create-cluster-token token)

    if [ -n "$CLUSTER_TOKEN" ]; then
        kubectl delete secret kotsadm-auto-create-cluster-token
    else
        CLUSTER_TOKEN=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)
    fi

    render_yaml_file "$DIR/addons/kotsadm/1.13.5/tmpl-secret-cluster-token.yaml" > "$DIR/kustomize/kotsadm/secret-cluster-token.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-cluster-token.yaml

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

    render_yaml_file "$DIR/addons/kotsadm/1.13.5/tmpl-secret-password.yaml" > "$DIR/kustomize/kotsadm/secret-password.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-password.yaml

    kubernetes_scale_down default deployment kotsadm
    kubernetes_scale_down default deployment kotsadm-api
}

function kotsadm_secret_postgres() {
    local POSTGRES_PASSWORD=$(kubernetes_secret_value default kotsadm-postgres password)

    if [ -n "$POSTGRES_PASSWORD" ]; then
        return 0
    fi

    POSTGRES_PASSWORD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)

    render_yaml_file "$DIR/addons/kotsadm/1.13.5/tmpl-secret-postgres.yaml" > "$DIR/kustomize/kotsadm/secret-postgres.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-postgres.yaml

    kubernetes_scale_down default deployment kotsadm
    kubernetes_scale_down default deployment kotsadm-api
    kubernetes_scale_down default deployment kotsadm-postgres
    kubernetes_scale_down default deployment kotsadm-migrations
}

function kotsadm_secret_s3() {
    render_yaml_file "$DIR/addons/kotsadm/1.13.5/tmpl-secret-s3.yaml" > "$DIR/kustomize/kotsadm/secret-s3.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-s3.yaml
}

function kotsadm_secret_session() {
    local JWT_SECRET=$(kubernetes_secret_value default kotsadm-session key)

    if [ -n "$JWT_SECRET" ]; then
        return 0
    fi

    JWT_SECRET=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c16)

    render_yaml_file "$DIR/addons/kotsadm/1.13.5/tmpl-secret-session.yaml" > "$DIR/kustomize/kotsadm/secret-session.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-session.yaml

    kubernetes_scale_down default deployment kotsadm
    kubernetes_scale_down default deployment kotsadm-api
}

function kotsadm_api_encryption_key() {
    local API_ENCRYPTION=$(kubernetes_secret_value default kotsadm-encryption encryptionKey)

    if [ -n "$API_ENCRYPTION" ]; then
        return 0
    fi

    # 24 byte key + 12 byte nonce, base64 encoded. This is separate from the base64 encoding used
    # in secrets with kubectl. Kotsadm expects the value to be encoded when read as an env var.
    API_ENCRYPTION=$(< /dev/urandom cat | head -c36 | base64)

    render_yaml_file "$DIR/addons/kotsadm/1.13.5/tmpl-secret-api-encryption.yaml" > "$DIR/kustomize/kotsadm/secret-api-encryption.yaml"
    insert_resources "$DIR/kustomize/kotsadm/kustomization.yaml" secret-api-encryption.yaml

    kubernetes_scale_down default deployment kotsadm-api
}

function kotsadm_api_patch_prometheus() {
    insert_patches_strategic_merge "$DIR/kustomize/kotsadm/kustomization.yaml" api-prometheus.yaml
    cp "$DIR/addons/kotsadm/1.13.5/patches/api-prometheus.yaml" "$DIR/kustomize/kotsadm/api-prometheus.yaml"
}

function kotsadm_metadata_configmap() {
    local src="$1"
    local dst="$2"

    # The application.yaml pre-exists from airgap bundle OR
    # gets created below if user specified the app-slug and metadata exists.
    if [ "$AIRGAP" != "1" ] && [ -n "$KOTSADM_APPLICATION_SLUG" ]; then
        # If slug exists, but there's no branding, then replicated.app will return nothing.
        # (application.yaml will remain empty)
        echo "Retrieving app metadata: url=$REPLICATED_APP_URL, slug=$KOTSADM_APPLICATION_SLUG"
        curl $REPLICATED_APP_URL/metadata/$KOTSADM_APPLICATION_SLUG > "$src/application.yaml"
    fi
    if test -s "$src/application.yaml"; then
        cp "$src/application.yaml" "$dst/"
        kubectl create configmap kotsadm-application-metadata --from-file="$dst/application.yaml" --dry-run -oyaml > "$dst/kotsadm-application-metadata.yaml"
        insert_resources $dst/kustomization.yaml kotsadm-application-metadata.yaml
    fi
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
CN = kotsadm.default.svc.cluster.local

[ req_ext ]
subjectAltName = @alt_names

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=nonRepudiation,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names

[ alt_names ]
DNS.1 = kotsadm
DNS.2 = kotsadm.default
DNS.3 = kotsadm.default.svc
DNS.4 = kotsadm.default.svc.cluster
DNS.5 = kotsadm.default.svc.cluster.local
IP.1 = $PRIVATE_ADDRESS
EOF
    if [ -n "$PUBLIC_ADDRESS" ]; then
        echo "IP.2 = $PUBLIC_ADDRESS" >> kotsadm.cnf
    fi

    openssl req -newkey rsa:2048 -nodes -keyout kotsadm.key -config kotsadm.cnf -x509 -days 365 -out kotsadm.crt -extensions v3_ext

    kubectl -n default create secret tls kotsadm-tls --key=kotsadm.key --cert=kotsadm.crt
    kubectl -n default annotate secret kotsadm-tls acceptAnonymousUploads=1

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

# TODO rotate
function kotsadm_kubelet_client_secret() {
    if kubernetes_resource_exists default secret kubelet-client-cert; then
        return 0
    fi

    kubectl -n default create secret generic kubelet-client-cert \
        --from-file=client.crt=/etc/kubernetes/pki/apiserver-kubelet-client.crt \
        --from-file=client.key=/etc/kubernetes/pki/apiserver-kubelet-client.key \
        --from-file=/etc/kubernetes/pki/ca.crt
}

function kotsadm_cli() {
    local src="$1"

    if ! kubernetes_is_master; then
        return 0
    fi
    if [ ! -f "$src/assets/kots.tar.gz" ] && [ "$AIRGAP" != "1" ]; then
        mkdir -p "$src/assets"
        curl -L "https://github.com/replicatedhq/kots/releases/download/v1.13.5/kots_linux_amd64.tar.gz" > "$src/assets/kots.tar.gz"
    fi

    pushd "$src/assets"
    tar xf "kots.tar.gz"
    mkdir -p "$KUBECTL_PLUGINS_PATH"
    mv kots "$KUBECTL_PLUGINS_PATH/kubectl-kots"
    popd

    # https://github.com/replicatedhq/kots/issues/149
    if [ ! -e /usr/lib64/libdevmapper.so.1.02.1 ] && [ -e /usr/lib64/libdevmapper.so.1.02 ]; then
        ln -s /usr/lib64/libdevmapper.so.1.02 /usr/lib64/libdevmapper.so.1.02.1
    fi
}

# copy pgdata from pvc named kotsadm-postgres to new pvc named kotsadm-postgres-kotsadm-postgres-0
# used by StatefulSet in 1.12.2+
function kotsadm_rename_postgres_pvc_1-12-2() {
    local src="$1"

    if kubernetes_resource_exists default deployment kotsadm-postgres; then
        kubectl delete deployment kotsadm-postgres
    fi
    if ! kubernetes_resource_exists default pvc kotsadm-postgres; then
        return 0
    fi
    printf "${YELLOW}Renaming PVC kotsadm-postgres to kotsadm-postgres-kotsadm-postgres-0${NC}\n"
    kubectl apply -f "$src/kotsadm-postgres-rename-pvc.yaml"
    spinner_until -1 kotsadm_postgres_pvc_renamed
    kubectl delete pod kotsadm-postgres-rename-pvc
    kubectl delete pvc kotsadm-postgres
}

function kotsadm_postgres_pvc_renamed {
    local status=$(kubectl get pod kotsadm-postgres-rename-pvc -ojsonpath='{ .status.containerStatuses[0].state.terminated.reason }')
    [ "$status" = "Completed" ]
}

function kotsadm_namespaces() {
    local src="$1"
    local dst="$2"

    IFS=',' read -ra KOTSADM_APPLICATION_NAMESPACES_ARRAY <<< "$KOTSADM_APPLICATION_NAMESPACES"
    for NAMESPACE in "${KOTSADM_APPLICATION_NAMESPACES_ARRAY[@]}"; do
        kubectl create ns "$NAMESPACE" 2>/dev/null || true
    done
}
