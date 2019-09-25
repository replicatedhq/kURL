
function kotsadm() {
   local src="$DIR/addons/kotsadm/0.9.4"
   local dst="$DIR/kustomize/kotsadm"

   cp "$src/kustomization.yaml" "$dst/"
   cp "$src/api.yaml" "$dst/"
   cp "$src/application-metadata.yaml" "$dst/"
   cp "$src/operator.yaml" "$dst/"
   cp "$src/postgres.yaml" "$dst/"
   cp "$src/schemahero.yaml" "$dst/"
   cp "$src/secrets.yaml" "$dst/"
   cp "$src/web.yaml" "$dst/"

   eval "echo \"$(cat tmpl-start-kotsadm-web.sh)\"" > "$dst/start-kotsadm-web.sh"

   kubectl delete pod kotsadm-migrations || true;

   kubectl apply -k "$dst/"
}
