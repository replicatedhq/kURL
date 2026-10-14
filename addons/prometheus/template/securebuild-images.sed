# Only rewrite image tags already published by SecureBuild.
s@quay\.io/prometheus/prometheus:v3\.15\.0-distroless(["'[:space:]]|$)@docker.io/kurlsh/prometheus:v3.15.0\1@g
s@docker\.io/grafana/grafana:13\.2\.2-distroless(["'[:space:]]|$)@docker.io/kurlsh/grafana:13.2.2\1@g
s@quay\.io/kiwigrid/k8s-sidecar:2\.11\.2(["'[:space:]]|$)@docker.io/kurlsh/kiwigrid-k8s-sidecar:2.11.2\1@g
s@quay\.io/prometheus/alertmanager:v0\.34\.1(["'[:space:]]|$)@docker.io/kurlsh/alertmanager:v0.34.1\1@g
s@quay\.io/prometheus/node-exporter:v1\.12\.1-distroless(["'[:space:]]|$)@docker.io/kurlsh/node-exporter:v1.12.1\1@g
s@quay\.io/prometheus-operator/prometheus-operator:v0\.94\.1(["'[:space:]]|$)@docker.io/kurlsh/prometheus-operator:v0.94.1\1@g
s@quay\.io/prometheus-operator/prometheus-config-reloader:v0\.94\.1(["'[:space:]]|$)@docker.io/kurlsh/prometheus-config-reloader:v0.94.1\1@g
s@registry\.k8s\.io/kube-state-metrics/kube-state-metrics:v2\.20\.0(["'[:space:]]|$)@docker.io/kurlsh/kube-state-metrics:v2.20.0\1@g
s@registry\.k8s\.io/prometheus-adapter/prometheus-adapter:v0\.12\.0(["'[:space:]]|$)@docker.io/kurlsh/prometheus-adapter:v0.12.0\1@g
