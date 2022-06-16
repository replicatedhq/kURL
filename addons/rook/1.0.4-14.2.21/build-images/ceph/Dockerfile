# https://github.com/ceph/ceph-container

FROM ceph/ceph:v14.2.21

RUN yum install -y \
    bind-license \
    binutils \
    cyrus-sasl-lib \
    expat \
    glib2 \
    krb5-libs \
    libldb \
    libwbclient \
    libxml2 \
    libxml2-python \
    nss \
    nss-sysinit \
    nss-tools \
    openldap \
    openssl \
    openssl-libs \
    rpm \
    rpm-build-libs \
    rpm-libs \
    rpm-python \
    samba-client-libs \
  && yum clean all

