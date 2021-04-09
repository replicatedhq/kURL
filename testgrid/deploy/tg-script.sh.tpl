#!/bin/bash

apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y

echo "Setting up RAID0 for openebs local storage."
apt install -y btrbk
mkfs.btrfs -d raid0 /dev/nvme0n1 /dev/nvme1n1
mkdir -p /var/openebs/local
mount /dev/nvme0n1 /var/openebs/local/

echo "Installing kURL"
INSTALL_SCRIPT=/root/kurl-install.sh
curl https://kurl.sh/f3dd2d4 > $INSTALL_SCRIPT
sed -i 's/parse_yaml_into_bash_variables$/parse_yaml_into_bash_variables\n    PRIVATE_ADDRESS=$(\/sbin\/ifconfig bond0:0 | awk "\/inet \/ {print \\$2}")/' $INSTALL_SCRIPT 
chmod +x $INSTALL_SCRIPT
./$INSTALL_SCRIPT
[ -d /root/.kube ] || mkdir /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
export KUBECONFIG=/root/.kube/config

echo "Removing OpenEbs webhook"
kubectl delete deployment openebs-admission-server -n openebs

echo "Instaling KubeVirt"
kubectl create namespace kubevirt
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v0.32.0/kubevirt-operator.yaml
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v0.32.0/kubevirt-cr.yaml
kubectl wait --timeout=180s --for=condition=Available -n kubevirt kv/kubevirt
kubectl create ns cdi
kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.24.0/cdi-operator.yaml
kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/v1.24.0/cdi-cr.yaml

echo "Installing krew KubeVirt plugin"
export HOME=/root
curl https://krew.sh/virt | bash

echo "Setting up tgrun service"
cat <<-TGRUND > /lib/systemd/system/tgrun.service
[Unit]
Description=tgrun

StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple

Restart=on-failure
RestartSec=5s

StandardOutput=syslog
StandardError=syslog
WorkingDirectory=/root
SyslogIdentifier=tgrund

Environment="KUBECONFIG=/etc/kubernetes/admin.conf"
Environment="HOME=/root"
Environment="PATH=/root/.krew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="DOCKERHUB_USERNAME=${dockerhub_username}"
Environment="DOCKERHUB_PASSWORD=${dockerhub_password}"
ExecStart=/bin/bash -c '/bin/tgrun run'

[Install]
WantedBy=multi-user.target
TGRUND

echo "pulling tgrun image and extracting binary"
docker pull replicated/tgrun:latest

docker create -ti --name dummy replicated/tgrun:latest bash
docker cp dummy:/bin/tgrun /bin/tgrun
docker rm -f dummy

systemctl start tgrun
