fluentd () {
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd-ns.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd-rbac.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd.yaml
}
