FROM amazonlinux
ARG KUBERNETES_VERSION
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
RUN mkdir -p /packages/archives

RUN yum install yum-utils -y
RUN yumdownloader --resolve --destdir=/packages/archives -y \
	kubelet-${KUBERNETES_VERSION} \
	kubectl-${KUBERNETES_VERSION} \
	kubernetes-cni \
	ncurses-compat-libs \
	git

CMD cp -r /packages/archives/* /out/
