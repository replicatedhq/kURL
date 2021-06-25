# https://github.com/ceph/ceph-container

FROM ceph/ceph:v14.2.21

RUN yum install -y \
    glib2 \
    libwbclient \
    libldb \
    samba-client-libs \
  && yum clean all

