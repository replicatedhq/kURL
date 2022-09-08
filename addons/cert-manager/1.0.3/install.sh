cert-manager() {
  local src="$DIR/addons/cert-manager/1.0.3"
  local dst="$DIR/kustomize/cert-manager"

  cp "$src/cert-manager.yaml" "$dst"
  cp "$src/kustomization.yaml" "$dst"

  kubectl apply -k  "$dst"

  # wait for deployments to be ready
  echo "awaiting cert-manager deployment"
  spinner_until 120 deployment_fully_updated cert-manager cert-manager
  echo "awaiting cert-manager-cainjector deployment"
  spinner_until 120 deployment_fully_updated cert-manager cert-manager-cainjector
  echo "awaiting cert-manager-webhook deployment"
  spinner_until 120 deployment_fully_updated cert-manager cert-manager-webhook
}
