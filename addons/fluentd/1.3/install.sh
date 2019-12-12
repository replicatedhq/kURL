# fluentd () {
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-ns.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-rbac.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-configmap.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_only/fluentd-daemonset.yaml
#     kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/test-log-generator.yaml
# }

fluentd () {
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/logging-ns.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/elasticsearch-svc.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/elasticsearch-statefulset.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/kibana.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/kibana-svc.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/fluentd-configmap.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/fluentd-rbac.yaml
    kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/fluentd_es_kibana/fluentd-daemonset.yaml
    #kubectl apply -f $DIR/addons/fluentd/$FLUENTD_VERSION/test-log-generator.yaml
}
