apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
metadata:
  name: kubelet-configuration
containerLogMaxSize: $CONTAINER_LOG_MAX_SIZE
