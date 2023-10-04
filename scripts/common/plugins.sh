export KUBECTL_PLUGINS_PATH=/usr/local/bin

function install_plugins() {
    pushd "$DIR/krew"
    tar xzf outdated.tar.gz --no-same-owner && chown root:root outdated && mv outdated /usr/local/bin/kubectl-outdated
    tar xzf preflight.tar.gz --no-same-owner && chown root:root preflight && mv preflight /usr/local/bin/kubectl-preflight
    tar xzf support-bundle.tar.gz --no-same-owner && chown root:root support-bundle && mv support-bundle /usr/local/bin/kubectl-support_bundle
    popd

    # uninstall system-wide krew from old versions of kurl
    rm -rf /opt/replicated/krew
    sed -i '/^export KUBECTL_PLUGINS_PATH.*KREW_ROOT/d' /etc/profile
    sed -i '/^export KREW_ROOT.*replicated/d' /etc/profile
}

function install_kustomize() {
    if ! kubernetes_is_master; then
        return 0
    elif [ ! -d "$DIR/packages/kubernetes/${k8sVersion}/assets" ]; then
        echo "Kustomize package is missing in your distribution. Skipping."
        return 0
    fi

    kustomize_dir=/usr/local/bin

    pushd "$DIR/packages/kubernetes/${k8sVersion}/assets"
    for file in $(ls kustomize-*);do
        if [ "${file: -6}" == "tar.gz" ];then
            tar xf ${file}
            chmod a+x kustomize
            mv kustomize /usr/local/bin/${file%%.tar*}
        else
            # Earlier versions of kustomize weren't archived/compressed
            chmod a+x ${file}
            cp ${file} ${kustomize_dir}
        fi
    done
    popd

    if ls ${kustomize_dir}/kustomize-* 1>/dev/null 2>&1;then 
        latest_binary=$(basename $(ls ${kustomize_dir}/kustomize-* | sort -V | tail -n 1))
        
        # Link to the latest version
        ln -s -f ${kustomize_dir}/${latest_binary} ${kustomize_dir}/kustomize
    fi
}
