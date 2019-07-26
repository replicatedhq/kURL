# Gather any additional information required from the user that could not be discovered and was not
# passed with a flag

function prompts() {
    if [ -z "$PRIVATE_ADDRESS" ]; then
        promptForPrivateIp
    fi
    # TODO public address? only required for adding SAN to K8s API server cert

    if [ "$NO_PROXY" != "1" ]; then
        if [ -z "$PROXY_ADDRESS" ]; then
            discoverProxy
        fi

        if [ -z "$PROXY_ADDRESS" ] && [ "$AIRGAP" != "1" ]; then
            promptForProxy
        fi

        if [ -n "$PROXY_ADDRESS" ]; then
            getNoProxyAddresses "$PRIVATE_ADDRESS" "$SERVICE_CIDR"
        fi
    fi
    return 0
}

promptForProxy() {
    printf "Does this machine require a proxy to access the Internet? "
    if ! confirmN; then
        return
    fi

    printf "Enter desired HTTP proxy address: "
    prompt
    if [ -n "$PROMPT_RESULT" ]; then
        if [ "${PROMPT_RESULT:0:7}" != "http://" ] && [ "${PROMPT_RESULT:0:8}" != "https://" ]; then
            echo >&2 "Proxy address must have prefix \"http(s)://\""
            exit 1
        fi
        PROXY_ADDRESS="$PROMPT_RESULT"
        printf "The installer will use the proxy at '%s'\n" "$PROXY_ADDRESS"
    fi
}

if [ -z "$READ_TIMEOUT" ]; then
    READ_TIMEOUT="-t 20"
fi

promptTimeout() {
    set +e
    if [ -z "$FAST_TIMEOUTS" ]; then
        read ${1:-$READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    else
        read ${READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    fi
    set -e
}

confirmY() {
    printf "(Y/n) "
    promptTimeout "$@"
    if [ "$PROMPT_RESULT" = "n" ] || [ "$PROMPT_RESULT" = "N" ]; then
        return 1
    fi
    return 0
}

confirmN() {
    printf "(y/N) "
    promptTimeout "$@"
    if [ "$PROMPT_RESULT" = "y" ] || [ "$PROMPT_RESULT" = "Y" ]; then
        return 0
    fi
    return 1
}

prompt() {
    set +e
    read PROMPT_RESULT < /dev/tty
    set -e
}

promptForPrivateIp() {
    _count=0
    _regex="^[[:digit:]]+: ([^[:space:]]+)[[:space:]]+[[:alnum:]]+ ([[:digit:].]+)"
    while read -r _line; do
        [[ $_line =~ $_regex ]]
        if [ "${BASH_REMATCH[1]}" != "lo" ]; then
            _iface_names[$((_count))]=${BASH_REMATCH[1]}
            _iface_addrs[$((_count))]=${BASH_REMATCH[2]}
            let "_count += 1"
        fi
    done <<< "$(ip -4 -o addr)"
    if [ "$_count" -eq "0" ]; then
        echo >&2 "Error: The installer couldn't discover any valid network interfaces on this machine."
        echo >&2 "Check your network configuration and re-run this script again."
        echo >&2 "If you want to skip this discovery process, pass the 'local-address' arg to this script, e.g. 'sudo ./install.sh local-address=1.2.3.4'"
        exit 1
    elif [ "$_count" -eq "1" ]; then
        PRIVATE_ADDRESS=${_iface_addrs[0]}
        printf "The installer will use network interface '%s' (with IP address '%s')\n" "${_iface_names[0]}" "${_iface_addrs[0]}"
        return
    fi
    printf "The installer was unable to automatically detect the private IP address of this machine.\n"
    printf "Please choose one of the following network interfaces:\n"
    for i in $(seq 0 $((_count-1))); do
        printf "[%d] %-5s\t%s\n" "$i" "${_iface_names[$i]}" "${_iface_addrs[$i]}"
    done
    while true; do
        printf "Enter desired number (0-%d): " "$((_count-1))"
        prompt
        if [ -z "$PROMPT_RESULT" ]; then
            continue
        fi
        if [ "$PROMPT_RESULT" -ge "0" ] && [ "$PROMPT_RESULT" -lt "$_count" ]; then
            PRIVATE_ADDRESS=${_iface_addrs[$PROMPT_RESULT]}
            printf "The installer will use network interface '%s' (with IP address '%s').\n" "${_iface_names[$PROMPT_RESULT]}" "$PRIVATE_ADDRESS"
            return
        fi
    done
}
