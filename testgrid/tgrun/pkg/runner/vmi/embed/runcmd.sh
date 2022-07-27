#!/bin/bash

source /opt/kurl-testgrid/common.sh

function run_install() {
    echo "preparing test at '$(date)'"

    AIRGAP=
    if echo "$KURL_URL" | grep -q "\.tar\.gz$" ; then
        AIRGAP=1
    fi
    AIRGAP_FLAG=

    if [ "$AIRGAP" = "1" ]; then
        AIRGAP_FLAG=airgap

        echo "downloading install bundle"

        curl -sSL -o install.tar.gz "$KURL_URL"
        if [ -n "$KURL_UPGRADE_URL" ]; then
            echo "downloading upgrade bundle"

            curl -sSL -o upgrade.tar.gz "$KURL_UPGRADE_URL"
        fi

        disable_internet

        tar -xzvf install.tar.gz
        local tar_exit_status="$?"
        if [ $tar_exit_status -ne 0 ]; then
            echo "failed to unpack airgap file with status $tar_exit_status"
            send_logs
            report_failure "airgap_download"
            report_status_update "failed"
            exit 1
        fi
    else
        curl -fsSL "$KURL_URL" > install.sh
        curl -fsSL "$KURL_URL/tasks.sh" > tasks.sh
    fi

    echo "running kurl install at '$(date)'"
    send_logs

    if [ "$NUM_PRIMARY_NODES" -gt 1 ]; then
        cat install.sh | timeout 30m bash -s $AIRGAP_FLAG ${KURL_FLAGS[@]} ekco-enable-internal-load-balancer
        KURL_EXIT_STATUS=$?
    else
        cat install.sh | timeout 30m bash -s $AIRGAP_FLAG ${KURL_FLAGS[@]}
        KURL_EXIT_STATUS=$?
    fi

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

    echo "kurl install complete at '$(date)'"
    send_logs
}

function run_upgrade() {
    AIRGAP_UPGRADE=
    if echo "$KURL_UPGRADE_URL" | grep -q "\.tar\.gz$" ; then
        AIRGAP_UPGRADE=1
    fi
    AIRGAP_UPGRADE_FLAG=

    if [ "$AIRGAP_UPGRADE" = "1" ]; then
        AIRGAP_UPGRADE_FLAG=airgap

        # run the upgrade
        tar -xzf upgrade.tar.gz
        local tar_exit_status="$?"
        if [ $tar_exit_status -ne 0 ]; then
            echo "failed to unpack airgap file with status $tar_exit_status"
            send_logs
            report_failure "airgap_download"
            report_status_update "failed"
            exit 1
        fi
    else
        curl -fsSL "$KURL_UPGRADE_URL" > install.sh
        curl -fsSL "$KURL_UPGRADE_URL/tasks.sh" > tasks.sh
    fi

    echo "running kurl upgrade at '$(date)'"
    send_logs

    cat install.sh | timeout 45m bash -s $AIRGAP_UPGRADE_FLAG ${KURL_FLAGS[@]}
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

    echo "kurl upgrade complete at '$(date)'"
    send_logs
}

function run_post_install_script() {
    if [ ! -f /opt/kurl-testgrid/postinstall.sh ] ; then
        return # file does not exist
    fi

    bash -euxo pipefail /opt/kurl-testgrid/postinstall.sh
    local exit_status="$?"

    send_logs

    if [ "$exit_status" -ne 0 ]; then
        report_failure "post_install_script"
        report_status_update "failed"
        collect_support_bundle
        exit 1
    fi
}

function run_post_upgrade_script() {
    if [ ! -f /opt/kurl-testgrid/postupgrade.sh ] ; then
        return # file does not exist
    fi

    bash -euxo pipefail /opt/kurl-testgrid/postupgrade.sh
    local exit_status="$?"

    send_logs

    if [ "$exit_status" -ne 0 ]; then
        report_failure "post_upgrade_script"
        report_status_update "failed"
        collect_support_bundle
        exit 1
    fi
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
    echo "node descriptions after completion:";
    kubectl describe nodes || true
    echo "";
}

function remove_first_element()
{
  local list=("$@")
  local rest_of_list=("${list[@]:1}")
  echo "${rest_of_list[@]}"
}

function remove_last_element()
{
  local list=("$@")
  local rest_of_list=("${list[@]:0:${#list[@]}-1}")
  echo "${rest_of_list[@]}"
}

function store_airgap_command() {
    joincommand=$(cat tasks.sh | sudo bash -s join_token $AIRGAP_FLAG ha)
    secondaryJoin=$(echo $joincommand | grep -o -P '(?<=following:).*(?=To)' | xargs echo -n)
    secondaryJoin=$(remove_first_element $secondaryJoin)
    secondaryJoin=$(remove_last_element $secondaryJoin)
    secondaryJoin=$(echo $secondaryJoin | base64 | tr -d '\n' )

    primaryJoin=$(echo $joincommand | grep -o -P '(?<=following:).*(?=)') # return from secondary till the end
    primaryJoin=$(echo $primaryJoin | grep -o -P '(?<=following:).*(?=)') # take the primary command only
    primaryJoin=$(remove_first_element $primaryJoin)
    primaryJoin=$(remove_last_element $primaryJoin)
    primaryJoin=$(echo $primaryJoin | base64 | tr -d '\n' )

    curl -X POST -d "{\"primaryJoin\": \"${primaryJoin}\",\"secondaryJoin\": \"${secondaryJoin}\"}" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/join-command"
    local exit_status="$?"
    if [ "$exit_status" -ne 0 ]; then
        echo "failed to store join command with status $exit_status"
        send_logs
        report_failure "join_command"
        report_status_update "failed"
        exit 1
    fi
}

function store_join_command() {
    joincommand=$(cat tasks.sh | sudo bash -s join_token $AIRGAP_FLAG ha)
    secondaryJoin=$(echo $joincommand | grep -o -P '(?<=nodes:).*(?=To)' | xargs echo -n)
    secondaryJoin=$(remove_first_element $secondaryJoin)
    secondaryJoin=$(remove_last_element $secondaryJoin)
    secondaryJoin=$(echo $secondaryJoin | base64 | tr -d '\n' )

    primaryJoin=$(echo $joincommand | grep -o -P '(?<=nodes:).*(?=)') # return from secondary till the end
    primaryJoin=$(echo $primaryJoin | grep -o -P '(?<=nodes:).*(?=)') # take the primary command only
    primaryJoin=$(remove_first_element $primaryJoin)
    primaryJoin=$(remove_last_element $primaryJoin)
    primaryJoin=$(echo $primaryJoin | base64 | tr -d '\n' )

    curl -X POST -d "{\"primaryJoin\": \"${primaryJoin}\",\"secondaryJoin\": \"${secondaryJoin}\"}" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/join-command"
    local exit_status="$?"
    if [ "$exit_status" -ne 0 ]; then
        echo "failed to store join command with status $exit_status"
        send_logs
        report_failure "join_command"
        report_status_update "failed"
        exit 1
    fi
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

    local packets=
    packets=$(iptables -L OUTPUT -v | grep "AIRGAP VIOLATION" | awk '{ print $1 }')
    if [ "$packets" -eq "0" ]; then
        return 0
    fi

    if [ -f "/var/log/messages" ]; then
        grep "AIRGAP VIOLATION" /var/log/messages
    fi
    if [ -f "/var/log/syslog" ]; then
        grep "AIRGAP VIOLATION" /var/log/syslog
    fi

    return 1
}

function disable_internet() {
    echo "disabling internet"

    local os_id="$(. /etc/os-release && echo "$ID")"
    local os_version_id="$(. /etc/os-release && echo "$VERSION_ID")"
    if [ "$OS_NAME" = "CentOS" ] && [ "$os_id" = "centos" ] && [ "$os_version_id" = "8" ]; then
      ##
      # Centos 8 has reached to EOL, It means that CentOS 8 will no longer receive development resources from the official CentOS project. 
      # After Dec 31st, 2021, if you need to update your CentOS, you need to change the mirrors to vault.centos.org where they will be archived permanently
      ##
      sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
      sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
    fi

    # get the list of testgrid API IPs
    command -v dig >/dev/null 2>&1 || { yum -y install bind-utils; }
    command -v iptables >/dev/null 2>&1 || { yum -y install iptables; }
    if [ -f /usr/lib64/libip4tc.so.2 ] && [ ! -f /usr/lib64/libip4tc.so.0 ]; then
        # On CentOS 8.1 `systemctl` commands don't work after installing iptables
        ln -s /usr/lib64/libip4tc.so.2 /usr/lib64/libip4tc.so.0
    fi
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
        if [ "${BASH_REMATCH[1]}" != "lo" ] && [ "${BASH_REMATCH[1]}" != "kube-ipvs0" ] && [ "${BASH_REMATCH[1]}" != "docker0" ] && [ "${BASH_REMATCH[1]}" != "weave" ] && [ "${BASH_REMATCH[1]}" != "antrea-gw0" ]; then
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
        report_status_update "failed"
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
        report_status_update "failed"
        exit 1
    fi

    # fix flake
    until /usr/local/bin/sonobuoy retrieve .; do sleep 10; done
    RESULTS=`ls | grep *_sonobuoy_*.tar.gz`
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
        report_status_update "failed"
        exit 1
    fi
}

function run_analyzers() {
    if [ -z "${SUPPORTBUNDLE_SPEC}" ]; then
        return 0
    fi

    echo "${SUPPORTBUNDLE_SPEC}" > ./supportbundle.yaml

    /usr/local/bin/kubectl-support_bundle ./supportbundle.yaml --interactive=false > ./analyzer-results.json
    cat ./analyzer-results.json

    if grep -q '"severity": "error"' ./analyzer-results.json ; then
        echo "failed troubleshoot analysis with errors"
        send_logs
        report_failure "troubleshoot_analysis"
        report_status_update "failed"
        exit 1
    elif grep -q '"severity": "warn"' ./analyzer-results.json ; then
        echo "failed troubleshoot analysis with warnings"
        send_logs
        report_failure "troubleshoot_analysis"
        report_status_update "failed"
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
    local failure="$1"

    if [ -n "$failure" ]; then
        curl -X POST -d "{\"success\": true, \"failureReason\": \"${failure}\"}" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/finish"
    else
        curl -X POST -d '{"success": true}' "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/finish"
    fi
}

function report_failure() {
    local failure="$1"
    curl -X POST -d "{\"success\": false, \"failureReason\": \"${failure}\"}" "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/finish"
}

function wait_for_cluster_ready() {
    i=0
    while true
    do
        ready_count=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l)
        # later we will check the dynamic value of the number of nodes
        if [ "$ready_count" -eq "$NUM_NODES" ]; then
            echo "cluster is ready"
            break
        fi
        echo "cluster is not ready"
        i=$((i+1))
        if [ $i -gt 20 ]; then
            send_logs
            report_failure "cluster_not_ready"
            report_status_update "failed"
            collect_support_bundle
            exit 1
        fi
        sleep 60
    done
}

# change flags from string to array with space as delimiter
function create_flags_array() {
    IFS=' ' read -r -a KURL_FLAGS <<< "${KURL_FLAGS}"
}

function main() {
    
    curl -X POST "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/running"
    setup_runner
 
    report_status_update "running"

    create_flags_array
    run_install
    
    if [ $KURL_EXIT_STATUS -ne 0 ]; then
        echo "kurl install failed"
        send_logs
        report_failure "kurl_install"
        report_status_update "failed"
        collect_support_bundle
        exit 1
    fi

    run_post_install_script

    run_tasks_join_token
    if [ "$(is_airgap)" = "1" ]; then
      store_airgap_command
    else
      store_join_command
    fi
    send_logs
    report_status_update "joinCommandStored"
    wait_for_cluster_ready

    if [ "$KURL_UPGRADE_URL" != "" ]; then
        run_upgrade

        if [ $KURL_EXIT_STATUS -ne 0 ]; then
            echo "kurl upgrade failed"
            send_logs
            report_failure "kurl_upgrade"
            report_status_update "failed"
            collect_support_bundle
            exit 1
        fi

        run_post_upgrade_script
    fi

    failureReason=""
    if ! check_airgap ; then
        failureReason="airgap_violation"
    fi

    collect_support_bundle

    run_sonobuoy

    run_analyzers

    send_logs
    report_status_update "success" # used to update the initialprimary node in the clusernode table
    report_success "$failureReason"
    exit 0
}

###############################################################################
# Globals
#
# TESTGRID_APIENDPOINT
# TEST_ID
# KURL_URL
# KURL_UPGRADE_URL
# SUPPORTBUNDLE_SPEC
#
###############################################################################

main
