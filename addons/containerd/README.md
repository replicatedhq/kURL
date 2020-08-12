Containerd is packaged as an add-on but it is installed before other add-ons since it is required by Kubernetes.
It does not need to define the normal add-on hooks (containerd, containerd_pre_init, containerd_join).
