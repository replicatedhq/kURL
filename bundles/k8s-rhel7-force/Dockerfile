FROM amazonlinux:2
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
ARG KUBERNETES_MINOR_VERSION
RUN sed -i "s/__KUBERNETES_MINOR_VERSION__/v${KUBERNETES_MINOR_VERSION}/g" /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yum install yum-utils -y
RUN yumdownloader --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	ncurses-compat-libs \
	git

CMD cp -r /packages/archives/* /out/
