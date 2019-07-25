FROM centos:7
ARG VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives
RUN yumdownloader --resolve --destdir=/packages/archives -y kubelet-$VERSION kubeadm-$VERSION kubectl-$VERSION kubernetes-cni

# First upgrade step requires upgraded kubeadm binary before kubeadm package is upgraded
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade-1-11/
RUN curl -sSL https://dl.k8s.io/release/v${VERSION}/bin/linux/amd64/kubeadm > /packages/archives/kubeadm

FROM busybox:latest
COPY --from=0 /packages /packages
CMD cp -r /packages/* /out/
