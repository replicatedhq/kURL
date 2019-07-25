
function render_yaml() {
	eval "echo \"$(cat $YAML_DIR/$1)\""
}
