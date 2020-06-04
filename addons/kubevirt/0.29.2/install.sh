function kubevirt() {
    local kubevirtoperatorsrc="$DIR/addons/kubevirt/0.29.2/kubevirt-operator"
    local kubevirtoperatordst="$DIR/kustomize/kubevirt-operator"
    local kubevirtcrsrc="$DIR/addons/kubevirt/0.29.2/kubevirt-cr"
    local kubevirtcrdst="$DIR/kustomize/kubevirt-cr"

    cp -r "$kubevirtoperatorsrc/" "$kubevirtoperatordst/"
    cp -r "$kubevirtcrsrc/" "$kubevirtcrdst/"

    kubectl apply -k "$kubevirtoperatordst/"
    kubectl apply -k "$kubevirtcrdst/"

    ## this addon includes CDI also
    local cdioperatorsrc="$DIR/addons/kubevirt/0.29.2/cdi-operator"
    local cdioperatordst="$DIR/kustomize/cdi-operator"
    local cdicrsrc="$DIR/addons/kubevirt/0.29.2/cdi-cr"
    local cdicrdst="$DIR/kustomize/cdi-cr"

    cp -r "$cdioperatorsrc/" "$cdioperatordst/"
    cp -r "$cdicrsrc/" "$cdicrdst/"

    kubectl apply -k "$cdioperatordst/"
    kubectl apply -k "$cdicrdst"

    install_virt_plugin
}

function install_virt_plugin() {
    pushd "$DIR/krew"
    ./krew-linux_amd64 install --manifest=virt.yaml --archive=virt.tar.gz > /dev/null 2>&1
    popd
}