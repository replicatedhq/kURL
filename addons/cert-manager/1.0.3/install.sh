cert-manager() {
  local src="$DIR/addons/cert-manager/1.0.3"
  local dst="$DIR/kustomize/cert-manager"

  cp "$src/cert-manager.yaml" "$dst"
  cp "$src/kustomization.yaml" "$dst"

  kubectl apply -k  "$dst"
}