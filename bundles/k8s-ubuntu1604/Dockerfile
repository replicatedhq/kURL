FROM ubuntu:16.04
ARG VERSION
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install curl apt-transport-https
RUN mkdir -p /packages
RUN  curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add
COPY ./kubernetes.list /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update
RUN apt-get install -d -y kubeadm=${VERSION}-00 kubelet=${VERSION}-00 kubectl=${VERSION}-00 kubernetes-cni -oDebug::NoLocking=1 -o=dir::cache=/packages/

# First upgrade step requires upgraded kubeadm binary before kubeadm package is upgraded
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
RUN curl -sSL https://dl.k8s.io/release/v${VERSION}/bin/linux/amd64/kubeadm > /packages/archives/kubeadm


FROM busybox:latest
COPY --from=0 /packages /packages
CMD cp -r /packages/* /out/
