# https://github.com/rook/rook/blob/v1.0.4/images/ceph/Dockerfile

FROM rook/ceph:v1.0.4 AS base

FROM ceph/ceph:v14.2.0

RUN yum install -y \
    bind-license \
    binutils \
    curl \
    cyrus-sasl-lib \
    expat \
    glib2 \
    glibc \
    glibc-common \
    krb5-libs \
    libcurl \
    libldb \
    libwbclient \
    libxml2 \
    libxml2-python \
    nettle \
    nss \
    nss-sysinit \
    nss-tools \
    openldap \
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
    rpm \
    rpm-build-libs \
    rpm-libs \
    rpm-python \
    samba-client-libs \
    sudo \
  && yum clean all

COPY --from=base /tini /tini

COPY --from=base /usr/local/bin/rook /usr/local/bin/rookflex /usr/local/bin/toolbox.sh /usr/local/bin/
COPY --from=base /etc/ceph-csi /etc/ceph-csi

ENTRYPOINT ["/tini", "--", "/usr/local/bin/rook"]
CMD [""]
