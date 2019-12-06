fluentd () {
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/example_app.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/rbac.yaml
}
