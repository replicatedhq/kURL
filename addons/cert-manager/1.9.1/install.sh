cert-manager() {
  local src="$DIR/addons/cert-manager/1.9.1"
  local dst="$DIR/kustomize/cert-manager"

  cp "$src/cert-manager.yaml" "$dst"
  cp "$src/kustomization.yaml" "$dst"


  # check if the current cert-manager version is v1.0.3 - if it is, skip the upgrade
  if kubectl get ns | grep -q cert-manager; then
    local certManagerImage=
    certManagerImage=$(kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}')
    if [ "$certManagerImage" == "quay.io/jetstack/cert-manager-controller:v1.0.3" ]; then
      kubectl delete MutatingWebhookConfiguration cert-manager-webhook
      kubectl delete namespace cert-manager

      kubectl get issuer -A -o yaml > "$dst/existingIssuers.yaml"

      kubectl delete crd certificaterequests.cert-manager.io certificates.cert-manager.io challenges.acme.cert-manager.io clusterissuers.cert-manager.io installers.cluster.kurl.sh issuers.cert-manager.io orders.acme.cert-manager.io || true
    fi
  fi

  kubectl apply -k  "$dst"

  # wait for deployments to be ready
  printf "awaiting cert-manager deployment\n"
  spinner_until 120 deployment_fully_updated cert-manager cert-manager
  printf "awaiting cert-manager-cainjector deployment\n"
  spinner_until 120 deployment_fully_updated cert-manager cert-manager-cainjector
  printf "awaiting cert-manager-webhook deployment\n"
  spinner_until 120 deployment_fully_updated cert-manager cert-manager-webhook

  if [ -f "$dst/existingIssuers.yaml" ]; then
    kubectl apply -f "$dst/existingIssuers.yaml" || true
    rm "$dst/existingIssuers.yaml"
  fi
}
