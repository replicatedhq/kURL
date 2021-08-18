The goal of this branch is to vet 


0. Spin up 2+ VMs

1. Run installer on 1st VM
2. Run join command on 2nd VM
3. Install sonobuoy on first command

wget https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.53.2/sonobuoy_0.53.2_linux_amd64.tar.gz
tar -xvf sonobuoy_0.53.2_linux_amd64.tar.gz
chmod +x sonobuoy
sudo mv sonobuoy /usr/bin/sonobuoy
sonobuoy run --mode=certified-conformance