# fluentd () {
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-ns.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-rbac.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-configmap.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-daemonset.yaml
# }

fluentd() {
    local src="$DIR/addons/fluentd/$FLUENTD_VERSION"
    local dst="$DIR/kustomize/fluentd"

    local logging_src="$src/logging"
    local logging_dst="$dst/logging"

    local fluentd_src="$src/fluentd"
    local fluentd_standalone_src="$src/fluentd_standalone"
    local fluentd_dst="$dst/fluentd"

    local elasticsearch_src="$src/elasticsearch"
    local elasticsearch_dst="$dst/elasticsearch"

    local kibana_src="$src/kibana"
    local kibana_dst="$dst/kibana"

    if [ "$FLUENTD_FULL_EFK_STACK" == 1 ]; then
        cp -r "$logging_src/" "$logging_dst/"
        cp -r "$fluentd_src/" "$fluentd_dst/"
        cp -r "$elasticsearch_src/" "$elasticsearch_dst/"
        cp -r "$kibana_src/" "$kibana_dst/"

        if [ -z "$FLUENTD_CONF_FILE" ]; then
            FLUENTD_CONF_FILE="$fluentd_dst/fluent.conf"
            REMOVE_FLUENTD_CONF=1
        fi

        kubectl create configmap fluentdconf --from-file $FLUENTD_CONF_FILE --namespace logging -o yaml --dry-run > "$fluentd_dst/fluentd-ekf-configmap.yaml"

        if [ -n "$REMOVE_FLUENTD_CONF" ]; then
            rm -f "$FLUENTD_CONF_FILE"
        fi

        kubectl apply -k "$logging_dst/"
        kubectl apply -k "$elasticsearch_dst/"
        kubectl apply -k "$kibana_dst/"
        kubectl apply -k "$fluentd_dst/"
    else
        cp -r "$logging_src/" "$logging_dst/"
        cp -r "$fluentd_standalone_src/" "$fluentd_dst/"

        if [ -z "$FLUENTD_CONF_FILE" ]; then
            FLUENTD_CONF_FILE="$fluentd_dst/fluent.conf"
            REMOVE_FLUENTD_CONF=1
        fi

        kubectl create configmap fluentdconf --from-file $FLUENTD_CONF_FILE --namespace logging -o yaml --dry-run > "$fluentd_dst/fluentd-fd-only-configmap.yaml"

        if [ -n "$REMOVE_FLUENTD_CONF" ]; then
            rm FLUENTD_CONF_FILE
        fi

        kubectl apply -k "$logging_dst/"
        kubectl apply -k "$fluentd_dst/"
    fi

}

fluentd_outro() {
    if [ "$FLUENTD_FULL_EFK_STACK" == 1 ]; then
        printf "\n"
        printf "\n"
        printf "The UI of Kibana has been exposed on NodePort ${GREEN}30887${NC}\n"
        printf "\n"
        printf "\n"
    fi
}
