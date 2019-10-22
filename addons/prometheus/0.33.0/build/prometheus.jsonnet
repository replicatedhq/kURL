// Reference info: documentation for https://github.com/ksonnet/ksonnet-lib can be found at http://g.bryan.dev.hepti.center
//
local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';  // https://github.com/ksonnet/ksonnet-lib/blob/master/ksonnet.beta.3/k.libsonnet - imports k8s.libsonnet
// * https://github.com/ksonnet/ksonnet-lib/blob/master/ksonnet.beta.3/k8s.libsonnet defines things such as "persistentVolumeClaim:: {"
//
local pvc = k.core.v1.persistentVolumeClaim;  // https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.11/#persistentvolumeclaim-v1-core (defines variable named 'spec' of type 'PersistentVolumeClaimSpec')

local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-kubeadm.libsonnet') +
  // Uncomment the following imports to enable its patches
  (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-node-ports.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-thanos-sidecar.libsonnet') +
  {
    _config+:: {
      namespace: 'monitoring',

      prometheus+:: {
        namespaces+: ['heptio-contour', 'rook-ceph', 'kurl'],
      },
    },

    prometheus+:: {
      prometheus+: {
        spec+: {
          retention: '15d',

          storage: {
            volumeClaimTemplate:
              pvc.new() +
              pvc.mixin.spec.withAccessModes('ReadWriteOnce') +
              pvc.mixin.spec.resources.withRequests({ storage: '10Gi' }),
          },  // storage
        },  // spec
      },  // prometheus
    },  // prometheus

  };

{ ['00namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
{ ['0prometheus-operator-' + name]: kp.prometheusOperator[name] for name in std.objectFields(kp.prometheusOperator) } +
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) }
