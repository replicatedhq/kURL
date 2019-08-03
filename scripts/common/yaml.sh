
function render_yaml() {
    if [ "$AIRGAP" != "1" ] && [ -n "$INSTALL_URL" ]; then
        mkdir -p $YAML_DIR
        curl $INSTALL_URL/dist/yaml/$1 > $YAML_DIR/$1
    fi
	eval "echo \"$(cat $YAML_DIR/$1)\""
}
