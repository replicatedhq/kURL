apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
metadata:
  name: kubelet-configuration
containerLogMaxFiles: $CONTAINER_LOG_MAX_FILES
