
function install_helm() {
    if [ -n "$HELM_HELMFILE_SPEC" ] && kubernetes_is_master; then

        BIN_HELM=$DIR/bin/helm
        BIN_HELMFILE=$DIR/bin/helmfile

        cp -f $DIR/helm/helm $DIR/bin
        cp -f $DIR/helm/helmfile $DIR/bin

    fi
}

function helmfile_sync() {

    if [ -z "$HELM_HELMFILE_SPEC" ]; then
        return 0
    fi

    logStep "Installing Helm Charts using the Helmfile Spec"

    # TODO (dan): add reporting for helm
    # report_helm_start

    printf "${HELM_HELMFILE_SPEC}" > helmfile-tmp.yaml

    if [ "$AIRGAP" != "1" ]; then
        $BIN_HELMFILE -b $BIN_HELM --file helmfile-tmp.yaml deps  # || report_helm_failure  #TODO (dan): add reporting
    fi    
    # TODO (dan): To support air gap case, we might need to modify the helmfile to always run the local chart
    
    $BIN_HELMFILE -b $BIN_HELM --file helmfile-tmp.yaml sync  # || report_helm_failure  #TODO (dan): add reporting

    rm helmfile-tmp.yaml

    # TODO (dan): add reporting for helm
    # report_helm_success
}

function helm_load() {
    if [ "$AIRGAP" = "1" ] && [ -n "$HELM_HELMFILE_SPEC" ] ; then
        # TODO (dan): Implement airgapped loading after bundler is updated
        bail "Airgap Installation with Helm is currently not supported"
        #load_images $DIR/helm-bundle/images
    fi    
}
