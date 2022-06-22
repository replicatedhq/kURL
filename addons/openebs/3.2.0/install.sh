function openebs_pre_init() {
    if [ -z "$OPENEBS_NAMESPACE" ]; then
        OPENEBS_NAMESPACE=openebs
    fi
    if [ -z "$OPENEBS_LOCALPV_STORAGE_CLASS" ]; then
        OPENEBS_LOCALPV_STORAGE_CLASS=openebs-localpv
    fi
    if [ -z "$OPENEBS_CSTOR_STORAGE_CLASS" ]; then
        OPENEBS_CSTOR_STORAGE_CLASS=openebs-cstor
    fi
    if [ -z "$OPENEBS_CSTOR_TARGET_REPLICATION" ]; then
        OPENEBS_CSTOR_TARGET_REPLICATION="3"
    fi
}

function openebs() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"
    local dst="$DIR/kustomize/openebs"

    render_yaml_file "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    cp "$src/openebs-operator.yaml" "$dst/"

    secure_openebs

    if [ "$OPENEBS_NAMESPACE" != "openebs" ]; then
        bail "the only supported namespace for OpenEBS 3.2.0 is 'openebs', not $OPENEBS_NAMESPACE."
    fi

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        report_addon_start "openebs-cstor" "3.2.0"

        bail "cstor is not yet supported on OpenEBS 3.2.0."

        report_addon_success "openebs-cstor" "3.2.0"
    fi

    if [ "$OPENEBS_LOCALPV" = "1" ]; then
        report_addon_start "openebs-localpv" "3.2.0"

        render_yaml_file "$src/tmpl-localpv-storage-class.yaml" > "$dst/localpv-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" localpv-storage-class.yaml

        if [ "$OPENEBS_LOCALPV_STORAGE_CLASS" = "default" ]; then
            render_yaml_file "$src/tmpl-patch-localpv-default.yaml" > "$dst/patch-localpv-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-localpv-default.yaml
        fi

        kubectl apply -k "$dst/"

        echo "awaiting localpv provisioner deployment health"
        spinnerPodRunning "$OPENEBS_NAMESPACE" "openebs-localpv-provisioner"

        echo "awaiting ndm operator deployment health"
        spinnerPodRunning "$OPENEBS_NAMESPACE" "openebs-ndm-operator"

        report_addon_success "openebs-localpv" "3.2.0"
    fi
}

function openebs_join() {
    secure_openebs
}

function secure_openebs() {
    mkdir -p /var/openebs
    chmod 700 /var/openebs
}
