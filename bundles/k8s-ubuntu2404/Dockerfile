FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get -y install curl apt-transport-https gnupg tzdata ca-certificates

RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

ARG KUBERNETES_MINOR_VERSION

RUN echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
RUN apt-get update

RUN mkdir -p /archives

ARG KUBERNETES_VERSION

RUN apt-get --print-uris --yes install  \
    kubeadm=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) | \
    grep ^\' | cut -d\' -f2 > ~/raw_urls.txt
RUN apt-get --print-uris --yes install  \
    kubelet=$(apt-cache madison kubeadm | grep ${KUBERNETES_VERSION}- | awk '{ print $3 }' | head -n 1) | \
    grep ^\' | cut -d\' -f2 >> ~/raw_urls.txt

RUN cat ~/raw_urls.txt | grep 'pkgs.k8s.io' > ~/urls.txt
RUN cd /archives && cat ~/urls.txt | xargs -I {} -n 1 curl -L -O {}
