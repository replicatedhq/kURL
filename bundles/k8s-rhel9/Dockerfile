FROM rockylinux:9

ARG KUBERNETES_VERSION

RUN echo -e "fastestmirror=1\nmax_parallel_downloads=8" >> /etc/dnf/dnf.conf
RUN yum install -y yum-utils createrepo modulemd-tools

COPY ./containertools /opt/containertools
COPY ./kubernetes.repo /etc/yum.repos.d/kubernetes.repo
ARG KUBERNETES_MINOR_VERSION
RUN sed -i "s/__KUBERNETES_MINOR_VERSION__/v${KUBERNETES_MINOR_VERSION}/g" /etc/yum.repos.d/kubernetes.repo

RUN mkdir -p /packages/archives
RUN /opt/containertools/yumdownloader.sh "kubelet-$KUBERNETES_VERSION kubectl-$KUBERNETES_VERSION kubernetes-cni"
RUN /opt/containertools/createrepo.sh
RUN /opt/containertools/builddeps.sh > /packages/archives/Deps \
	&& sort /packages/archives/Deps | uniq | grep -v '^[[:space:]]*$' > /packages/archives/Deps.tmp \
	&& mv /packages/archives/Deps.tmp /packages/archives/Deps

RUN echo "git" >> /packages/archives/Deps

CMD cp -r /packages/archives/* /out/
