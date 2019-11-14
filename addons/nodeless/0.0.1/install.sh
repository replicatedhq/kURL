
function nodeless() {
    create_webhook_certs

    cp "$DIR/addons/nodeless/0.0.1/kustomization.yaml" "$DIR/kustomize/nodeless/kustomization.yaml"
    render_yaml_file "$DIR/addons/nodeless/0.0.1/ip-masq-agent.yaml" > "$DIR/kustomize/nodeless/ip-masq-agent.yaml"
    render_yaml_file "$DIR/addons/nodeless/0.0.1/kiyot-device-plugin.yaml" > "$DIR/kustomize/nodeless/kiyot-device-plugin.yaml"
    render_yaml_file "$DIR/addons/nodeless/0.0.1/kiyot-kube-proxy.yaml" > "$DIR/kustomize/nodeless/kiyot-kube-proxy.yaml"
    render_yaml_file "$DIR/addons/nodeless/0.0.1/kiyot-webhook.yaml" > "$DIR/kustomize/nodeless/kiyot-webhook.yaml"
    render_yaml_file "$DIR/addons/nodeless/0.0.1/kiyot.yaml" > "$DIR/kustomize/nodeless/kiyot.yaml"
    kubectl apply -k "$DIR/kustomize/nodeless/"
}

function nodeless_pre_init() {
    replace_cri

    cp "$DIR/addons/nodeless/0.0.1/kubeadm-init-config-v1beta2.yml" "$DIR/kustomize/kubeadm/init-patches/nodeless-kubeadm-init-config-v1beta2.yml"
    cp "$DIR/addons/nodeless/0.0.1/kubeproxy-config-v1alpha1.yml" "$DIR/kustomize/kubeadm/init-patches/nodeless-kubeproxy-config-v1alpha1.yml"
}

function nodeless_join() {
    replace_cri

    cp "$DIR/addons/nodeless/0.0.1/kubeadm-join-config-v1beta2.yaml" "$DIR/kustomize/kubeadm/join-patches/nodeless-kubeadm-join-config-v1beta2.yaml"
}

function set_cri_socket() {
    CRI_SOCKET=/run/criproxy.sock
}

function replace_cri() {
    set_cri_socket
    install_criproxy
    override_procinfo
}

function install_criproxy() {
    containerd config default > /etc/containerd/config.toml
    curl -fsSL https://github.com/elotl/criproxy/releases/download/v0.15.0/criproxy > /tmp/criproxy
    curl -fsSL https://github.com/elotl/criproxy/releases/download/v0.15.0/criproxy.sha1 > /tmp/criproxy.sha1
    pushd /tmp > /dev/null; sha1sum -c criproxy.sha1 > /dev/null; popd > /dev/null
    install -m 755 -o root -g root /tmp/criproxy /usr/local/bin/criproxy
    cat <<EOF > /etc/systemd/system/criproxy.service
[Unit]
Description=CRI Proxy
Wants=containerd.service

[Service]
ExecStart=/usr/local/bin/criproxy -v 3 -logtostderr -connect /run/containerd/containerd.sock,kiyot:/run/milpa/kiyot.sock -listen $CRI_SOCKET
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=kubelet.service
EOF
    systemctl daemon-reload
    systemctl disable docker
    systemctl enable containerd
    systemctl restart containerd
    systemctl enable criproxy
    systemctl restart criproxy
}

function override_procinfo() {
    # Override number of CPUs and memory cadvisor reports.
    local infodir=/opt/kiyot/proc
    mkdir -p $infodir; rm -f $infodir/{cpu,mem}info
    for i in $(seq 0 1023); do
        cat << EOF >> $infodir/cpuinfo
processor	: $i
physical id	: 0
core id		: 0
cpu MHz		: 2400.068
EOF
    done

    local mem=$((4096*1024*1024))
    cat << EOF > $infodir/meminfo
$(printf "MemTotal:%15d kB" $mem)
SwapTotal:             0 kB
EOF

    cat <<EOF > /etc/systemd/system/kiyot-override-procinfo.service
[Unit]
Description=Override /proc info files
Before=kubelet.service

[Service]
Type=oneshot
ExecStart=/bin/mount --bind $infodir/cpuinfo /proc/cpuinfo
ExecStart=/bin/mount --bind $infodir/meminfo /proc/meminfo
RemainAfterExit=true
ExecStop=/bin/umount /proc/cpuinfo
ExecStop=/bin/umount /proc/meminfo
StandardOutput=journal
EOF
    systemctl daemon-reload
    systemctl enable kiyot-override-procinfo
    systemctl restart kiyot-override-procinfo
}

function create_webhook_certs() {
    local service=kiyot-webhook-svc
    local secret=kiyot-webhook-certs
    local namespace=kube-system
    local csrName=${service}.${namespace}
    local tmpdir=$(mktemp -d)

    cat <<EOF >> ${tmpdir}/csr.conf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${service}
DNS.2 = ${service}.${namespace}
DNS.3 = ${service}.${namespace}.svc
EOF

    openssl genrsa -out ${tmpdir}/server-key.pem 2048
    openssl req -new -key ${tmpdir}/server-key.pem -subj "/CN=${service}.${namespace}.svc" -out ${tmpdir}/server.csr -config ${tmpdir}/csr.conf

    # Clean up any previously created CSR for our service. Ignore errors if not present.
    kubectl delete csr ${csrName} 2>/dev/null || true

    # create server cert/key CSR and send to k8s API
    cat <<EOF | kubectl create -f -
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: ${csrName}
spec:
  groups:
  - system:authenticated
  request: $(cat ${tmpdir}/server.csr | base64 | tr -d '\n')
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

    # verify CSR has been created
    while true; do
        kubectl get csr ${csrName}
        if [ "$?" -eq 0 ]; then
            break
        fi
    done

    # approve and fetch the signed certificate
    kubectl certificate approve ${csrName}
    # verify certificate has been signed
    for x in $(seq 300); do
        local serverCert=$(kubectl get csr ${csrName} -o jsonpath='{.status.certificate}')
        if [[ ${serverCert} != '' ]]; then
            break
        fi
        sleep 1
    done
    if [[ ${serverCert} == '' ]]; then
        echo "ERROR: After approving csr ${csrName}, the signed certificate did not appear on the resource." >&2
        exit 1
    fi
    echo ${serverCert} | openssl base64 -d -A -out ${tmpdir}/server-cert.pem

    # create the secret with CA cert and server cert/key
    kubectl create secret generic ${secret} \
            --from-file=key.pem=${tmpdir}/server-key.pem \
            --from-file=cert.pem=${tmpdir}/server-cert.pem \
            --dry-run -o yaml |
        kubectl -n ${namespace} apply -f -
    
    CA_BUNDLE=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')
}
