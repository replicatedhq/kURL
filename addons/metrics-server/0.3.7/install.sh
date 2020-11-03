metrics-server() {
  local src="$DIR/addons/metrics-server/0.3.7"
  local dst="$DIR/kustomize/metrics-server"

  cp "$src/components.yaml" "$dst"
  cp "$src/kubelet-insecure-tls.yaml" "$dst"
  cp "$src/kustomization.yaml" "$dst"

  kubectl apply -k  "$dst"
}