# Only rewrite image tags already published by SecureBuild.
s@docker\.io/rook/ceph:v1\.19\.7(["'[:space:]]|$)@docker.io/kurlsh/rook-ceph:v1.19.7\1@g
s@quay\.io/ceph/ceph:v19\.2\.4(["'[:space:]]|$)@docker.io/kurlsh/ceph:v19.2.4\1@g
s@quay\.io/cephcsi/cephcsi:v3\.16\.2(["'[:space:]]|$)@docker.io/kurlsh/cephcsi:v3.16.2\1@g
s@quay\.io/cephcsi/ceph-csi-operator:v0\.6\.0(["'[:space:]]|$)@docker.io/kurlsh/ceph-csi-operator:v0.6.0\1@g
s@registry\.k8s\.io/sig-storage/csi-node-driver-registrar:v2\.16\.0(["'[:space:]]|$)@docker.io/kurlsh/csi-node-driver-registrar:v2.16.0\1@g
s@registry\.k8s\.io/sig-storage/csi-resizer:v2\.1\.0(["'[:space:]]|$)@docker.io/kurlsh/csi-resizer:v2.1.0\1@g
s@registry\.k8s\.io/sig-storage/csi-provisioner:v6\.1\.1(["'[:space:]]|$)@docker.io/kurlsh/csi-provisioner:v6.1.1\1@g
s@registry\.k8s\.io/sig-storage/csi-snapshotter:v8\.5\.0(["'[:space:]]|$)@docker.io/kurlsh/csi-snapshotter:v8.5.0\1@g
s@registry\.k8s\.io/sig-storage/csi-attacher:v4\.11\.0(["'[:space:]]|$)@docker.io/kurlsh/csi-attacher:v4.11.0\1@g
s@quay\.io/csiaddons/k8s-sidecar:v0\.14\.0(["'[:space:]]|$)@docker.io/kurlsh/csiaddons-k8s-sidecar:v0.14.0\1@g
