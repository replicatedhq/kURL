#!/bin/bash

function command_exists() {
    command -v "$@" > /dev/null 2>&1
}

function setup_runner() {
    setenforce 0 || true # rhel variants

    echo "$TEST_ID" > /tmp/testgrid-id

    if [ ! -c /dev/urandom ]; then
        /bin/mknod -m 0666 /dev/urandom c 1 9 && /bin/chown root:root /dev/urandom
    fi

    echo "OS INFO:"
    cat /etc/*-release
    echo ""
}

function run_install() {
    AIRGAP=
    if echo "$KURL_URL" | grep -q "\.tar\.gz$" ; then
        AIRGAP=1
    fi
    AIRGAP_FLAG=

    if [ "$AIRGAP" = "1" ]; then
        AIRGAP_FLAG=airgap

        # get the install bundle
        curl -fsSL -o install.tar.gz "$KURL_URL"
        if [ -n "$KURL_UPGRADE_URL" ]; then
            curl -fsSL -o upgrade.tar.gz "$KURL_UPGRADE_URL"
        fi

        disable_internet

        # run the installer
        tar -xzvf install.tar.gz
        local tar_exit_status="$?"
        if [ $tar_exit_status -ne 0 ]; then
            echo "failed to unpack airgap file with status $tar_exit_status"
            send_logs
            report_failure "airgap_download"
            exit 1
        fi
    else
        curl -fsSL "$KURL_URL" > install.sh
        curl -fsSL "$KURL_URL/tasks.sh" > tasks.sh
    fi

    cat install.sh | timeout 30m bash -s $AIRGAP_FLAG
    KURL_EXIT_STATUS=$?

    export KUBECONFIG=/etc/kubernetes/admin.conf
    export PATH=$PATH:/usr/local/bin

    # rke2
    export PATH=$PATH:/var/lib/rancher/rke2/bin
    if [ -f /etc/rancher/rke2/rke2.yaml ]; then
        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
        # On testgrid the hostname doesn't resolve, so configure the apiserver to connect to kubelet
        # by IP. Otherwise sonobuoy retrieve will fail execing into the sonobuoy pod. Kubeadm does
        # this by default.
        sed -i '/kubelet-client-key/a\    - --kubelet-preferred-address-types=InternalIP' /var/lib/rancher/rke2/agent/pod-manifests/kube-apiserver.yaml
    fi
    if [ -f /var/lib/rancher/rke2/agent/etc/crictl.yaml ]; then
        export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml
    fi

    # k3s
    if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    fi
    if [ -f /var/lib/rancher/k3s/agent/etc/crictl.yaml ]; then
        export CRI_CONFIG_FILE=/var/lib/rancher/k3s/agent/etc/crictl.yaml
    fi

    if [ "$KURL_EXIT_STATUS" -eq 0 ]; then
        echo ""
        echo "completed kurl install"
        echo ""
        echo "kubectl version:"
        kubectl version
    else
        echo ""
        echo "failed kurl install with exit status $KURL_EXIT_STATUS"
    fi

    collect_debug_info_after_kurl || true
}

function run_upgrade() {
    echo "upgrading installation"

    AIRGAP_UPGRADE=
    if echo "$KURL_UPGRADE_URL" | grep -q "\.tar\.gz$" ; then
        AIRGAP_UPGRADE=1
    fi
    AIRGAP_UPGRADE_FLAG=

    if [ "$AIRGAP_UPGRADE" = "1" ]; then
        AIRGAP_UPGRADE_FLAG=airgap

        # run the upgrade
        tar -xzvf upgrade.tar.gz
        local tar_exit_status="$?"
        if [ $tar_exit_status -ne 0 ]; then
            echo "failed to unpack airgap file with status $tar_exit_status"
            send_logs
            report_failure "airgap_download"
            exit 1
        fi
    else
        curl -fsSL "$KURL_UPGRADE_URL" > install.sh
        curl -fsSL "$KURL_UPGRADE_URL/tasks.sh" > tasks.sh
    fi

    cat install.sh | timeout 30m bash -s $AIRGAP_UPGRADE_FLAG
    KURL_EXIT_STATUS=$?

    if [ "$KURL_EXIT_STATUS" -eq 0 ]; then
        echo ""
        echo "completed kurl upgrade"
        echo ""
        echo "kubectl version:"
        kubectl version
    else
        echo ""
        echo "failed kurl upgrade with exit status $KURL_EXIT_STATUS"
    fi

    collect_debug_info_after_kurl || true
}

function collect_debug_info_after_kurl() {
    if [ "$KURL_EXIT_STATUS" -ne 0 ]; then
        echo "kubelet status"
        systemctl status kubelet

        echo "kubelet journalctl"
        journalctl -xeu kubelet

        echo "docker containers"
        if command_exists "docker" ; then
            docker ps -a
        elif command_exists "crictl" ; then
            crictl ps -a
        fi
    fi

    echo "";
    echo "running pods after completion:";
    kubectl get pods -A || true
    echo "";
}

function run_tasks_join_token() {
    # TODO: rke2 and k3s
    if command_exists "kubeadm" ; then
        echo "tasks.sh run:"
        cat tasks.sh | timeout 5m bash -s join_token $AIRGAP_FLAG
        echo "tasks exit status: $?"
        # TODO: failure
        echo ""
    fi
}

function check_airgap() {
    if ! echo "$KURL_URL" | grep -q "\.tar\.gz$" ; then
        return 0
    fi
    echo "check for outbound requests"

    local packets=$(iptables -L OUTPUT -v | grep "AIRGAP VIOLATION" | awk '{ print $1 }')
    if [ "$packets" -eq "0" ]; then
        return 0
    fi

    if [ -f "/var/log/messages" ]; then
        grep "AIRGAP VIOLATION" /var/log/messages
    fi
    if [ -f "/var/log/syslog" ]; then
        grep "AIRGAP VIOLATION" /var/log/syslog
    fi

    send_logs
    report_failure "airgap_violation"
    exit 1
}

function disable_internet() {
    echo "disabling internet"

    # get the list of testgrid API IPs
    command -v dig >/dev/null 2>&1 || { yum -y install bind-utils; }
    command -v iptables >/dev/null 2>&1 || { yum -y install iptables; }
    TESTGRID_DOMAIN=$(echo "$TESTGRID_APIENDPOINT" | sed -e "s.^https://..")
    echo "testgrid API endpoint: $TESTGRID_APIENDPOINT domain: $TESTGRID_DOMAIN"
    APIENDPOINT_IPS=$(dig "$TESTGRID_DOMAIN" | grep 'IN A' | awk '{ print $5 }')
    # and allow access to them
    for i in $APIENDPOINT_IPS; do
        echo "allowing access to $i"
        iptables -A OUTPUT -p tcp -d $i -j ACCEPT # accept comms to testgrid API IPs
    done

    # allow access to the local IP(s)
    _count=0
    _regex="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+[[:alnum:]]+ ([[:digit:].]+)"
    while read -r _line; do
        [[ $_line =~ $_regex ]]
        if [ "${BASH_REMATCH[1]}" != "lo" ] && [ "${BASH_REMATCH[1]}" != "kube-ipvs0" ] && [ "${BASH_REMATCH[1]}" != "docker0" ] && [ "${BASH_REMATCH[1]}" != "weave" ]; then
            _iface_names[$((_count))]=${BASH_REMATCH[1]}
            _iface_addrs[$((_count))]=${BASH_REMATCH[2]}
            let "_count += 1"
        fi
    done <<< "$(ip -4 -o addr)"
    for i in $_iface_addrs; do
        echo "allowing access to local address $i"
        iptables -A OUTPUT -p tcp -d $i -j ACCEPT # accept comms to testgrid API IPs
    done

    # disable internet by adding restrictive iptables rules
    iptables -A OUTPUT -p tcp -d 127.0.0.0/8 -j ACCEPT # accept comms to localhost
    iptables -A OUTPUT -p tcp -d 10.0.0.0/8 -j ACCEPT # accept comms to internal IPs
    iptables -A OUTPUT -p tcp -d 172.16.0.0/12 -j ACCEPT # accept comms to internal IPs
    iptables -A OUTPUT -p tcp -d 192.168.0.0/16 -j ACCEPT # accept comms to internal IPs
    iptables -A OUTPUT -p tcp -d 169.254.0.0/16 -j ACCEPT # accept link-local comms
    iptables -A OUTPUT -p tcp -j REJECT # reject comms to other IPs

    iptables -L

    echo "testing disabled internet"
    curl -v --connect-timeout 5 --max-time 5 "http://www.google.com"
    local exit_status="$?"
    if [ $exit_status -eq 0 ]; then
        echo "successfully curled an external endpoint in airgap"
        traceroute www.google.com
        send_logs
        report_failure "airgap_instance"
        exit 1
    fi

    local i="$(iptables -L OUTPUT --line-numbers | tail -n 1 | awk '{ print $1 }')"
    iptables -I OUTPUT "$i" -p tcp -j LOG --log-level 4 --log-prefix "AIRGAP VIOLATION: "

    echo "internet disabled"
}

function run_sonobuoy() {
    if kubectl version --short | grep -q "v1.16"; then
        echo "skipping sonobuoy on 1.16"
        return 0
    fi
    echo "running sonobuoy"

    # wait for 10 minutes for sonobuoy run to complete
    # skip preflights for now cause we pre-create the namespace and preflights will fail if it exists
    /usr/local/bin/sonobuoy run \
        --wait=10 \
        --image-pull-policy IfNotPresent \
        --mode quick

    SONOBUOY_EXIT_STATUS=$?
    if [ $SONOBUOY_EXIT_STATUS -ne 0 ]; then
        echo "failed sonobuoy run"
        collect_debug_info_sonobuoy
        send_logs
        report_failure "sonobuoy_run"
        exit 1
    fi

    RESULTS=$(/usr/local/bin/sonobuoy retrieve)
    if [ -n "$RESULTS" ]; then
        echo "completed sonobuoy run"
        /usr/local/bin/sonobuoy results "$RESULTS" > ./sonobuoy-results.txt
        curl -X POST --data-binary "@./sonobuoy-results.txt" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/sonobuoy"

        # print detailed results to log
        /usr/local/bin/sonobuoy results --mode=detailed "$RESULTS"

        return 0
    else
        echo "failed sonobuoy retrieve"
        collect_debug_info_sonobuoy
        send_logs
        report_failure "sonobuoy_retrieve"
        exit 1
    fi
}

function collect_debug_info_sonobuoy() {
    kubectl -n sonobuoy get pods
    kubectl -n sonobuoy describe pod sonobuoy || true
    kubectl -n sonobuoy logs sonobuoy || true
}

function collect_support_bundle() {
    echo "collecting support bundle"

    /usr/local/bin/kubectl-support_bundle https://kots.io
    SUPPORT_BUNDLE=$(ls -1 ./ | grep support-bundle-)
    if [ -n "$SUPPORT_BUNDLE" ]; then
        echo "completed support bundle collection"
        curl -X POST --data-binary "@./$SUPPORT_BUNDLE" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/bundle"
    else
        echo "failed support bundle collection"
    fi
}

function report_success() {
    curl -X POST -d '{"success": true}' "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/finish"
}

function report_failure() {
    local failure="$1"
    curl -X POST -d "{\"success\": false, \"failureReason\": \"${failure}\"}" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/finish"
}

function send_logs() {
    curl -X POST --data-binary "@/var/log/cloud-init-output.log" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/logs"
}

function main() {
    curl -X POST "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/running"

    echo "running kurl installer"

    setup_runner

    run_install
    send_logs

    if [ $KURL_EXIT_STATUS -ne 0 ]; then
        send_logs
        report_failure "kurl_install"
        collect_support_bundle
        exit 1
    fi

    run_tasks_join_token

    if [ "$KURL_UPGRADE_URL" != "" ]; then
        run_upgrade
        send_logs
    fi

    if [ $KURL_EXIT_STATUS -ne 0 ]; then
        send_logs
        report_failure "kurl_upgrade"
        collect_support_bundle
        exit 1
    fi

    check_airgap

    collect_support_bundle

    run_sonobuoy

    send_logs
    report_success
    exit 0
}

###############################################################################
# Globals
#
# TESTGRID_APIENDPOINT
# TEST_ID
# KURL_URL
# KURL_UPGRADE_URL
#
###############################################################################

main
