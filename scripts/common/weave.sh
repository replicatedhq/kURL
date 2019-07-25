
function weave() {
    logStep "deploy weave network"

    # disabling airgap upgrades of Weave until we solve image distribution
    if [ "$AIRGAP" = "1" ] && kubectl -n kube-system get ds weave-net &>/dev/null; then
        return
    fi

    sleeve=0
    local secret=0
    if [ "$ENCRYPT_NETWORK" != "0" ]; then
        secret=1
        if kubectl -n kube-system get secrets | grep -q weave-passwd ; then
            secret=0
        fi
        # Encrypted traffic cannot use the fast database on kernels below 4.2
        kernel_major=$(uname -r | cut -d'.' -f1)
        kernel_minor=$(uname -r | cut -d'.' -f2)
        if [ "$kernel_major" -lt "4" ]; then
            sleeve=1
        elif [ "$kernel_major" -lt "5" ] && [ "$kernel_minor" -lt "3" ]; then
            sleeve=1
        fi

        if [ "$sleeve" = "1" ]; then
            printf "${YELLOW}This host will not be able to establish optimized network connections with other peers in the Kubernetes cluster.\nRefer to the Replicated networking guide for help.\n\nhttp://help.replicated.com/docs/kubernetes/customer-installations/networking/${NC}\n"
        fi
    fi

    sh /tmp/kubernetes-yml-generate.sh $YAML_GENERATE_OPTS weave_yaml=1 weave_secret=$secret > /tmp/weave.yml

    kubectl apply -f /tmp/weave.yml -n kube-system
    logSuccess "weave network deployed"
}
