
// first version of each is "latest"
module.exports.InstallerVersions = {
  kubernetes: [
    "1.19.16",
    "1.19.15",
    "1.19.13",
    "1.19.12",
    "1.19.11",
    "1.19.10",
    "1.19.9",
    "1.19.7",
    "1.19.3",
    "1.19.2",
    "1.18.20",
    "1.18.19",
    "1.18.18",
    "1.18.17",
    "1.18.10",
    "1.18.9",
    "1.18.4",
    "1.17.13",
    "1.17.7",
    "1.17.3",
    "1.16.4",
    // cron-kubernetes-update-126
    "1.26.1",
    "1.26.0",
    // cron-kubernetes-update-125
    "1.25.6",
    "1.25.5",
    "1.25.4",
    "1.25.3",
    "1.25.2",
    "1.25.1",
    "1.25.0",
    // cron-kubernetes-update-124
    "1.24.10",
    "1.24.9",
    "1.24.8",
    "1.24.7",
    "1.24.6",
    "1.24.5",
    "1.24.4",
    "1.24.3",
    "1.24.0",
    // cron-kubernetes-update-123
    "1.23.16",
    "1.23.15",
    "1.23.14",
    "1.23.13",
    "1.23.12",
    "1.23.11",
    "1.23.10",
    "1.23.9",
    "1.23.6",
    "1.23.5",
    "1.23.3",
    "1.23.2",
    // cron-kubernetes-update-122
    "1.22.17",
    "1.22.16",
    "1.22.15",
    "1.22.14",
    "1.22.13",
    "1.22.12",
    "1.22.9",
    "1.22.8",
    "1.22.6",
    "1.22.5",
    "1.21.14",
    "1.21.12",
    "1.21.11",
    "1.21.9",
    "1.21.8",
    "1.21.5", 
    "1.21.4", 
    "1.21.3", 
    "1.21.2", 
    "1.21.1", 
    "1.21.0",
    "1.20.15",
    "1.20.14",
    "1.20.11", 
    "1.20.10", 
    "1.20.9", 
    "1.20.8", 
    "1.20.7", 
    "1.20.6", 
    "1.20.5", 
    "1.20.4", 
    "1.20.2", 
    "1.20.1", 
    "1.20.0",
  ],
  docker: [
    "20.10.17",
    "20.10.5",
    "19.03.15",
    "19.03.10",
    "19.03.4",
    "18.09.8",
  ],
  containerd: [
    "1.6.16", "1.6.15", "1.6.14", "1.6.13", "1.6.12", "1.6.11", "1.6.10", "1.6.9", "1.6.8", "1.6.7", "1.6.6", "1.6.4", "1.5.11", "1.5.10", // cron-containerd-update
    "1.4.13", "1.4.12", "1.4.11", "1.4.10", "1.4.9", "1.4.8", "1.4.6", "1.4.4", "1.4.3", "1.3.9", "1.3.7", "1.2.13",
  ],
  weave: [
    // cron-weave-update-265
    "2.6.5-20221122",
    "2.6.5-20221025",
    "2.6.5-20221006",
    "2.6.5-20220825",
    "2.6.5-20220720",
    "2.6.5-20220616",
    "2.6.5",
    "2.6.4",
    "2.5.2",
    // cron-weave-update
    "2.8.1-20230130",
    "2.8.1-20221122",
    "2.8.1-20221025",
    "2.8.1-20221006",
    "2.8.1-20220825",
    "2.8.1-20220720",
    "2.8.1-20220616",
    "2.8.1",
    "2.7.0",
  ],
  antrea: [
    // cron-antrea-update
    "1.4.0",
    "1.2.1",
    "1.2.0",
    "1.1.0",
    "1.0.1",
    "1.0.0",
    "0.13.1",
  ],
  flannel: [
    // cron-flannel-update
    "0.21.1",
    "0.21.0",
    "0.20.2",
    "0.20.1",
    "0.20.0",
  ],
  rook: [
    "1.0.4",
    // cron-rook-update
    "1.10.8",
    "1.10.6",
    "1.9.12",
    "1.8.10",
    "1.7.11",
    "1.6.11",
    "1.5.12",
    "1.5.11",
    "1.5.10",
    "1.5.9",
    "1.4.9",
    "1.4.3",
    "1.0.4-14.2.21",
  ],
  contour: ["1.24.1", "1.24.0", "1.23.2", "1.23.1", "1.23.0", "1.22.1", "1.22.0", "1.21.1", "1.21.0", "1.20.1", "1.20.0", "1.19.1", "1.18.0", "1.16.0", "1.15.1", "1.14.1", "1.14.0", "1.13.1", "1.13.0", "1.12.0", "1.11.0", "1.10.1", "1.7.0", "1.0.1", "0.14.0"], // cron-contour-update
  registry: [
    // cron-registry-update
    "2.8.1",
    "2.7.1",
  ],
  prometheus: [
    // cron-prometheus-update
    "0.62.0-44.3.1",
    "0.60.1-41.7.3",
    "0.59.1-40.1.0",
    "0.58.0-39.12.1",
    "0.58.0-39.11.0",
    "0.58.0-39.9.0",
    "0.58.0-39.4.0",
    "0.57.0-36.2.0",
    "0.57.0-36.0.3",
    "0.56.2-35.2.0",
    "0.53.1-30.1.0",
    "0.49.0-17.1.3",
    "0.49.0-17.1.1",
    "0.49.0-17.0.0",
    "0.48.1-16.12.1",
    "0.48.1-16.10.0",
    "0.48.0-16.1.2",
    "0.47.1-16.0.1",
    "0.47.0-15.3.1",
    "0.47.0-15.2.1",
    "0.47.0-15.2.0",
    "0.46.0-14.9.0",
    "0.46.0",
    "0.44.1",
    "0.33.0",
  ],
  fluentd: [
    "1.7.4",
  ],
  kotsadm: [
    "1.86.0",
    "1.85.0",
    "1.84.0",
    "1.83.0",
    "1.82.0",
    "1.81.1",
    "1.81.0",
    "1.80.0",
    "1.79.0",
    "1.78.0",
    "1.77.0",
    "1.76.1",
    "1.76.0",
    "1.75.0",
    "1.74.0",
    "1.73.0",
    "1.72.2",
    "1.72.1",
    "1.72.0",
    "1.71.0",
    "1.70.1",
    "1.70.0",
    "1.69.1",
    "1.69.0",
    "1.68.0",
    "1.67.0",
    "1.66.0",
    "1.65.0",
    "1.64.0",
    "1.63.0",
    "1.62.0",
    "1.61.0",
    "1.60.0",
    "1.59.3",
    "1.59.2",
    "1.59.1",
    "1.59.0",
    "1.58.2",
    "1.58.1",
    "1.58.0",
    "1.57.0",
    "1.56.0",
    "1.55.0",
    "1.54.0",
    "1.53.0",
    "1.52.1",
    "1.52.0",
    "1.51.0",
    "1.50.2",
    "1.50.1",
    "1.50.0",
    "1.49.0",
    "1.48.1",
    "1.48.0",
    "1.47.3",
    "1.47.2",
    "1.47.1",
    "1.47.0",
    "1.46.0",
    "1.45.0",
    "1.44.1",
    "1.44.0",
    "1.43.2",
    "1.43.1",
    "1.43.0",
    "1.42.1",
    "1.42.0",
    "1.41.1",
    "1.41.0",
    "1.40.0",
    "1.39.1",
    "1.39.0",
    "1.38.1",
    "1.38.0",
    "1.37.0",
    "1.36.1",
    "1.36.0",
    "1.35.0",
    "1.34.0",
    "1.33.2",
    "1.33.1",
    "1.33.0",
    "1.32.0",
    "1.31.1",
    "1.31.0",
    "1.30.0",
    "1.29.3",
    "1.29.2",
    "1.29.1",
    "1.29.0",
    "1.28.0",
    "1.27.1",
    "1.27.0",
    "1.26.0",
    "1.25.2",
    "1.25.1",
    "1.25.0",
    "1.24.2",
    "1.24.1",
    "1.24.0",
    "1.23.1",
    "1.23.0",
    "1.22.4",
    "1.22.3",
    "1.22.2",
    "1.22.1",
    "1.22.0",
    "1.21.3",
    "1.21.2",
    "1.21.1",
    "1.21.0",
    "1.20.3",
    "1.20.2",
    "1.20.1",
    "1.20.0",
    "1.19.6",
    "1.19.5",
    "1.19.4",
    "1.19.3",
    "1.19.2",
    "1.19.1",
    "1.19.0",
    "1.18.1",
    "1.18.0",
    "1.17.2",
    "1.17.1",
    "1.17.0",
    "1.16.2",
    "1.16.1",
    "1.16.0",
    "1.15.5",
    "1.15.4",
    "1.15.3",
    "1.15.2",
    "1.15.1",
    "1.15.0",
    "1.14.2",
    "1.14.1",
    "1.14.0",
    "1.13.9",
    "1.13.8",
    "1.13.6",
    "1.13.5",
    "1.13.4",
    "1.13.3",
    "1.13.2",
    "1.13.1",
    "1.13.0",
    "1.12.2",
    "1.12.1",
    "1.12.0",
    "1.11.4",
    "1.11.3",
    "1.11.2",
    "1.11.1",
    "1.10.3",
    "1.10.2",
    "1.10.1",
    "1.10.0",
    "1.9.1",
    "1.9.0",
    "1.8.0",
    "1.7.0",
    "1.6.0",
    "1.5.0",
    "1.4.1",
    "1.4.0",
    "1.3.0",
    "1.2.0",
    "1.1.0",
    "1.0.1",
    "1.0.0",
    "0.9.15",
    "0.9.14",
    "0.9.13",
    "0.9.12",
    "0.9.11",
    "0.9.10",
    "0.9.9",
  ],
  velero: [
    // cron-velero-update
    "1.10.1",
    "1.9.5",
    "1.9.4",
    "1.9.3",
    "1.9.2",
    "1.9.1",
    "1.9.0",
    "1.8.1",
    "1.7.1",
    "1.6.2",
    "1.6.1",
    "1.6.0",
    "1.5.4",
    "1.5.3",
    "1.5.1",
    "1.2.0",
  ],
  openebs: [
    // cron-openebs-update-3
    "3.4.0",
    "3.3.0",
    "3.2.0",
    // cron-openebs-update-2
    "2.12.9",
    "2.6.0",
    "1.12.0",
    "1.6.0",
  ],
  minio: [
    // cron-minio-update
    "2023-02-10T18-48-39Z",
    "2023-02-09T05-16-53Z",
    "2023-01-31T02-24-19Z",
    "2023-01-25T00-19-54Z",
    "2023-01-20T02-05-44Z",
    "2023-01-18T04-36-38Z",
    "2023-01-12T02-06-16Z",
    "2023-01-06T18-11-18Z",
    "2023-01-02T09-40-09Z",
    "2022-12-12T19-27-27Z",
    "2022-10-20T00-55-09Z",
    "2022-10-15T19-57-03Z",
    "2022-10-08T20-11-00Z",
    "2022-10-05T14-58-27Z",
    "2022-10-02T19-29-29Z",
    "2022-09-25T15-44-53Z",
    "2022-09-17T00-09-45Z",
    "2022-09-07T22-25-02Z",
    "2022-09-01T23-53-36Z",
    "2022-08-22T23-53-06Z",
    "2022-08-02T23-59-16Z",
    "2022-07-17T15-43-14Z",
    "2022-07-06T20-29-49Z",
    "2022-06-11T19-55-32Z",
    "2020-01-25T02-50-51Z",
  ],
  collectd: [
    "v5",
    "0.0.1",
  ],
  ekco: [
    // cron-ekco-update
    "0.26.3",
    "0.26.2",
    "0.26.1",
    "0.26.0",
    "0.25.0",
    "0.24.1",
    "0.24.0",
    "0.23.2",
    "0.23.1",
    "0.23.0",
    "0.22.0",
    "0.21.1",
    "0.21.0",
    "0.20.0",
    "0.19.9",
    "0.19.6",
    "0.19.3",
    "0.19.2",
    "0.19.1",
    "0.19.0",
    "0.18.0",
    "0.17.0",
    "0.16.0",
    "0.15.0",
    "0.14.0",
    "0.13.0",
    "0.12.0",
    "0.11.0",
    "0.10.3",
    "0.10.2",
    "0.10.1",
    "0.10.0",
    "0.9.0",
    "0.8.0",
    "0.7.0",
    "0.6.0",
    "0.5.0",
    "0.4.2",
    "0.4.1",
    "0.4.0",
    "0.3.0",
    "0.2.4",
    "0.2.3",
    "0.2.1",
    "0.2.0",
    "0.1.0",
  ],
  certManager: [
    "1.0.3",
    "1.9.1",
  ],
  metricsServer: [
    // cron-metrics-server-update
    "0.6.2",
    "0.3.7",
    "0.4.1",
  ],
  longhorn: [
    // cron-longhorn-update
    "1.3.1",
    "1.2.4",
    "1.2.2",
    "1.1.2",
    "1.1.1",
    "1.1.0",
  ],
  sonobuoy: [
    // cron-sonobuoy-update
    "0.56.15",
    "0.56.14",
    "0.56.13",
    "0.56.12",
    "0.56.11",
    "0.56.10",
    "0.56.8",
    "0.56.7",
    "0.55.1",
    "0.53.0",
    "0.52.0",
    "0.50.0",
  ],
  goldpinger: [
    // cron-goldpinger-update
    "3.7.0-5.5.0",
    "3.6.1-5.4.2",
    "3.5.1-5.2.0",
    "3.3.0-5.1.0",
    "3.2.0-5.0.0",
    "3.2.0-4.2.1",
    "3.2.0-4.1.1",
  ],
  aws: [
    "0.1.0",
  ],
};
