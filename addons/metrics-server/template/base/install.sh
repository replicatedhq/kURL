metrics-server() {
  local src="$DIR/addons/metrics-server/__METRICS_VERSION__"
  local dst="$DIR/kustomize/metrics-server"

  cp "$src/components.yaml" "$dst"
  cp "$src/kubelet-insecure-tls.yaml" "$dst"
  cp "$src/kustomization.yaml" "$dst"

  kubectl apply -k  "$dst"

  printf "awaiting metrics-server deployment\n"
  spinner_until 120 deployment_fully_updated kube-system metrics-server
}
