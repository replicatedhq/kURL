# https://github.com/rook/rook/blob/v1.0.4/images/ceph/Dockerfile

FROM rook/ceph:v1.0.4 AS base

FROM ceph/ceph:v14.2.21

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
    nss \
    nss-sysinit \
    nss-tools \
    openldap \
  && yum clean all

COPY --from=base /tini /tini

COPY --from=base /usr/local/bin/rook /usr/local/bin/rookflex /usr/local/bin/toolbox.sh /usr/local/bin/
COPY --from=base /etc/ceph-csi /etc/ceph-csi

ENTRYPOINT ["/tini", "--", "/usr/local/bin/rook"]
CMD [""]
