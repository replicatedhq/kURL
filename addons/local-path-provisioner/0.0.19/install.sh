function local-path-provisioner() {
  local src="$DIR/addons/local-path-provisioner/$LOCAL_PATH_PROVISIONER_VERSION"
  local dst="$DIR/kustomize/local-path-provisioner"

  local-path-provisioner_host_init

  cp "$src/driver.yaml" "$dst/"
  cp "$src/namespace.yaml" "$dst/"
  cp "$src/rbac.yaml" "$dst/"
  cp "$src/settings-configmap.yaml" "$dst/"
  cp "$src/storageclass.yaml" "$dst/"

  cp "$src/kustomization.yaml" "$dst/"

  kubectl apply -k "$dst/"
}

function local-path-provisioner_join() {
  local-path-provisioner_host_init
}

function local-path-provisioner_host_init() {
  mkdir -p /opt/local-path-provisioner
  chmod 700 /opt/local-path-provisioner
}
