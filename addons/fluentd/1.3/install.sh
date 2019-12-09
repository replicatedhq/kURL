fluentd () {
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd-ns.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd-rbac.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd-configmap.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd-daemonset.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/test-log-generator.yaml
}
