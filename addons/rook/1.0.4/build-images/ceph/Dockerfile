# https://github.com/ceph/ceph-container

FROM ceph/ceph:v14.2.0

RUN yum install -y \
    bind-license \
    curl \
    glibc \
    glibc-common \
    libcurl \
    libwbclient \
    openssl \
    openssl-libs \
    perl \
    perl-Pod-Escapes \
    perl-libs \
    perl-macros \
    python \
    python-devel \
    python-libs \
    python-rtslib \
    python3 \
    python3-libs \
    samba-client-libs \
    sudo \
    libldb \
    nettle \
  && yum clean all
