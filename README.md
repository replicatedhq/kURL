<div align="center">
  <img alt="Kurl-logo" src="https://kurl.sh/kurl_logo@2x.png" />
</div>
<br/>

kURL
====================================

kURL is a Kubernetes installer for airgapped and online clusters.

kURL relies on `kubeadm` to bring up the Kubernetes control plane, but there are a variety of tasks a system administrator must perform both before and after running kubeadm init in order to have a production-ready Kubernetes cluster, such as installing Docker, configuring Pod networking, or installing kubeadm itself.
The purpose of this installer is to automate those tasks so that any user can deploy a Kubernetes cluster with a single script.

## Getting Started
For more information please see [kurl.sh/docs/](https://kurl.sh/docs/)

# Community

For questions about using kURL, there's a [Replicated Community](https://help.replicated.com/community) forum, and a [#kurl channel in Kubernetes Slack](https://kubernetes.slack.com/channels/kurl).

# Notifications

kURL offers several optional [add-ons](https://kurl.sh/add-ons) for Kubernetes cluster creation. These open-source technology add-ons are distributed under various open-source licenses.

One optional add-on available for object storage is [MinIO](https://github.com/minio/minio). Use of MinIO is governed by the GNU AGPLv3 license that can be found in their [License](https://github.com/minio/minio/blob/master/LICENSE) file.

One optional add-on available for Metrics & Monitoring is Prometheus via the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), which includes Grafana. Use of Grafana is currently governed by the GNU AGPL v3 license that can be found in their [License](https://github.com/grafana/grafana/blob/main/LICENSE) file. 

