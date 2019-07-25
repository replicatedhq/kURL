FROM ubuntu:18.04
RUN apt-get update
RUN apt-get -y install wget curl apt-transport-https
RUN mkdir -p /packages
RUN wget -O /packages/cni.tar.gz https://github.com/containernetworking/plugins/releases/download/v0.7.5/cni-plugins-amd64-v0.7.5.tgz

FROM busybox:latest
COPY --from=0 /packages /packages
CMD cp -r /packages/* /out/
