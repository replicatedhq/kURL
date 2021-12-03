FROM registry.access.redhat.com/ubi7/ubi:7.9 AS builder
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yumdownloader --installroot=/tmp/empty-directory --releasever=/ --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	kubernetes-cni \
	git

# installing "createrepo" package on rhel requires a subscription. it's only needed to create the repo,
# and it's not part of the produced packages, so we can do this:
FROM centos:7
COPY --from=builder /packages/archives /packages/archives
RUN yum install -y createrepo
RUN createrepo /packages/archives

CMD cp -r /packages/archives/* /out/
