apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
metadata:
  name: kubelet-configuration
kubeReserved:
  cpu: "$cpu_millicores_to_reserve"m
  ephemeral-storage: "1Gi"
  memory: "$mebibytes_to_reserve"Mi
