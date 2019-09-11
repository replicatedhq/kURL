
function check_nodeless {
    logStep "Check if this is a nodeless setup"
    NODE_NAME="$(hostname -f)"
    CRI_SOCKET=""
    NODELESS_SUFFIX=""
    if [ "$NODELESS" = "1" ]; then
        CRI_SOCKET="/run/criproxy.sock"
        NODELESS_SUFFIX="-nodeless"
    fi
}

function install_milpa() {
    # Create a default storage class, backed by EBS.
    cat <<EOF > /tmp/storageclass.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: default
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/aws-ebs
volumeBindingMode: Immediate
reclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/storageclass.yaml

    # Set up ip-masq-agent.
    mkdir -p /tmp/ip-masq-agent-config
    cat <<EOF > /tmp/ip-masq-agent-config/config
nonMasqueradeCIDRs:
  - ${POD_CIDR}
$(for subnet in ${SUBNET_CIDR}; do echo "  - $subnet"; done)
EOF
    kubectl create -n kube-system configmap ip-masq-agent --from-file=/tmp/ip-masq-agent-config/config
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-incubator/ip-masq-agent/master/ip-masq-agent.yaml
    kubectl patch -n kube-system daemonset ip-masq-agent --patch '{"spec":{"template":{"spec":{"tolerations":[{"effect":"NoSchedule","key":"node-role.kubernetes.io/master"}]}}}}'

    # Start a kube-proxy deployment for Milpa. This will route cluster IP traffic
    # from Milpa pods.
    # TODO: myechuri: if needed, add nodeSeletor for milpa kube-proxy deployment.
    cat <<EOF > /tmp/kube-proxy-milpa.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
      annotations:
        kubernetes.io/target-runtime: kiyot
    spec:
      containers:
      - command:
        - /usr/local/bin/kube-proxy
        - --config=/var/lib/kube-proxy/config.conf
        - --hostname-override=$NODE_NAME
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        image: k8s.gcr.io/kube-proxy:v1.15.0
        name: kube-proxy
        resources: {}
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/lib/kube-proxy
          name: kube-proxy
      dnsPolicy: ClusterFirst
      hostNetwork: true
      priorityClassName: system-node-critical
      restartPolicy: Always
      securityContext: {}
      serviceAccount: kube-proxy
      serviceAccountName: kube-proxy
      terminationGracePeriodSeconds: 30
      volumes:
      - configMap:
          defaultMode: 420
          name: kube-proxy
        name: kube-proxy
EOF
    kubectl apply -f /tmp/kube-proxy-milpa.yaml

    # TODO: myechuri: add nodeSelector to Kiyot DaemonSet.
    cat <<EOF > /tmp/kiyot-ds.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: milpa-config
  namespace: kube-system
data:
  SERVICE_CIDR: "${SERVICE_CIDR}"
  server.yml: |
    apiVersion: v1
    cloud:
      aws:
        region: "us-east-1"
        imageOwnerID: 689494258501
    etcd:
      internal:
        dataDir: /opt/milpa/data
    nodes:
      defaultInstanceType: "t3.nano"
      extraCIDRs:
      - "${POD_CIDR}"
      itzo:
        url: ""
        version: ""
    license:
      key: ""
      id: ""
      username: ""
      password: ""
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kiyot
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kiyot-role
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - get
  - list
  - watch
  - create
  - delete
  - deletecollection
  - patch
  - update
- apiGroups:
  - kiyot.elotl.co
  resources:
  - cells
  verbs:
  - get
  - list
  - watch
  - create
  - delete
  - deletecollection
  - patch
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kiyot
roleRef:
  kind: ClusterRole
  name: kiyot-role
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: kiyot
  namespace: kube-system
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kiyot
  namespace: kube-system
spec:
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: kiyot
    spec:
      priorityClassName: "system-node-critical"
      restartPolicy: Always
      hostNetwork: true
      serviceAccountName: kiyot
      initContainers:
      - name: milpa-init
        image: elotl/milpa
        command:
        - bash
        - -c
        - "/milpa-init.sh /opt/milpa"
        volumeMounts:
        - name: optmilpa
          mountPath: /opt/milpa
        - name: server-yml
          mountPath: /etc/milpa
      containers:
      - name: kiyot
        image: elotl/milpa
        command:
        - /kiyot
        - --stderrthreshold=1
        - --logtostderr
        - --cert-dir=/opt/milpa/certs
        - --listen=/run/milpa/kiyot.sock
        - --milpa-endpoint=127.0.0.1:54555
        - --service-cluster-ip-range=\$(SERVICE_CIDR)
        - --kubeconfig=
        - --host-rootfs=/host-rootfs
        env:
        - name: SERVICE_CIDR
          valueFrom:
            configMapKeyRef:
              name: milpa-config
              key: SERVICE_CIDR
        securityContext:
          privileged: true
        volumeMounts:
        - name: optmilpa
          mountPath: /opt/milpa
        - name: run-milpa
          mountPath: /run/milpa
        - name: host-rootfs
          mountPath: /host-rootfs
          mountPropagation: HostToContainer
        - name: xtables-lock
          mountPath: /run/xtables.lock
        - name: lib-modules
          mountPath: /lib/modules
          readOnly: true
      - name: milpa
        image: elotl/milpa
        command:
        - /milpa
        - --stderrthreshold=1
        - --logtostderr
        - --cert-dir=/opt/milpa/certs
        - --config=/etc/milpa/server.yml
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        volumeMounts:
        - name: optmilpa
          mountPath: /opt/milpa
        - name: server-yml
          mountPath: /etc/milpa
        - name: etc-machineid
          mountPath: /etc/machine-id
          readOnly: true
      volumes:
      - name: optmilpa
        hostPath:
          path: /opt/milpa
          type: DirectoryOrCreate
      - name: server-yml
        configMap:
          name: milpa-config
          items:
          - key: server.yml
            path: server.yml
            mode: 0600
      - name: etc-machineid
        hostPath:
          path: /etc/machine-id
      - name: run-milpa
        hostPath:
          path: /run/milpa
      - name: host-rootfs
        hostPath:
          path: /
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: lib-modules
        hostPath:
          path: /lib/modules
EOF
    kubectl apply -f /tmp/kiyot-ds.yaml
}

function install_containerd() {
    # Configure containerd. This assumes kubenet is used for networking.
    echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/k8s.conf
    echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
    echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.d/k8s.conf
    sysctl --system
    mkdir -p /etc/cni/net.d
    mkdir -p /etc/containerd
    cat <<EOF > /etc/containerd/config.toml
[plugins.cri]
  [plugins.cri.cni]
    conf_template = "/etc/containerd/cni-template.json"
EOF
    cat <<EOF > /etc/containerd/cni-template.json
{
  "cniVersion": "0.3.1",
  "name": "containerd-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "promiscMode": true,
      "ipam": {
        "type": "host-local",
        "subnet": "{{.PodCIDR}}",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF
    systemctl restart containerd
}

function install_criproxy() {
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
    systemctl restart criproxy
}

function replace_cri() {
    install_containerd
    install_criproxy
    override_procinfo
}

function override_procinfo() {
    # Override number of CPUs and memory cadvisor reports.
    infodir=/opt/kiyot/proc
    mkdir -p $infodir; rm -f $infodir/{cpu,mem}info
    for i in $(seq 0 1023); do
        cat << EOF >> $infodir/cpuinfo
processor	: $i
physical id	: 0
core id		: 0
cpu MHz		: 2400.068
EOF
    done

    mem=$((4096*1024*1024))
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
    systemctl restart kiyot-override-procinfo
}
