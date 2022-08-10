# https://github.com/rook/rook/blob/v1.0.4/images/ceph/Dockerfile

FROM rook/ceph:v1.0.4 AS base

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

COPY --from=base /tini /tini

COPY --from=base /usr/local/bin/rook /usr/local/bin/rookflex /usr/local/bin/toolbox.sh /usr/local/bin/
COPY --from=base /etc/ceph-csi /etc/ceph-csi

ENTRYPOINT ["/tini", "--", "/usr/local/bin/rook"]
CMD [""]
