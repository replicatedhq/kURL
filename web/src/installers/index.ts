import * as crypto from "crypto";
import * as yaml from "js-yaml";
import * as _ from "lodash";
import * as mysql from "promise-mysql";
import { Service } from "@tsed/common";
import Ajv, {KeywordCxt} from "ajv";
import * as semver from "semver";
import { MysqlWrapper } from "../util/services/mysql";
import { instrumented } from "monkit";
import { Forbidden } from "../server/errors";
import {getDistUrl, getPackageUrl} from "../util/package";
import fetch from "node-fetch";
import { getInstallerVersions } from "./installer-versions";

interface ErrorResponse {
  error: any;
}

export interface KubernetesConfig {
  version: string;
  s3Override?: string;
  serviceCidrRange?: string;
  serviceCIDR?: string;
  HACluster?: boolean;
  masterAddress?: string;
  loadBalancerAddress?: string;
  containerLogMaxSize?: string;
  containerLogMaxFiles?: number;
  bootstrapToken?: string;
  bootstrapTokenTTL?: string;
  kubeadmTokenCAHash?: string;
  useStandardNodePortRange?: boolean;
  controlPlane?: boolean;
  certKey?: string;
}

export const kubernetesConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    serviceCidrRange: { type: "string", flag: "service-cidr-range", description: "The size of the CIDR for Kubernetes (can be presented as just a number or with a preceding slash)" },
    serviceCIDR: { type: "string", flag: "service-cidr", description: "This defines subnet for kubernetes" },
    HACluster: { type: "boolean", flag: "ha", description: "Create the cluster as a high availability cluster (note that this needs a valid load balancer address and additional nodes to be a truly HA cluster)" },
    masterAddress: { type: "string", flag: "kuberenetes-master-address", description: "The address of the internal Kubernetes API server, used during join scripts (read-only)" },
    loadBalancerAddress: { type: "string", flag: "load-balancer-address", description: "Used for High Availability installs, indicates the address of the external load balancer" },
    containerLogMaxSize: { type: "string", flag: "container-log-max-size", description: "A quantity defining the maximum size of the container log file before it is rotated. For example: \"5Mi\" or \"256Ki\". This does not work with Docker. For Docker, check out https://docs.docker.com/config/containers/logging/json-file." },
    containerLogMaxFiles: { type: "number", flag: "container-log-max-files", description: "Specifies the maximum number of container log files that can be present for a container. This does not work with Docker. For Docker, check out https://docs.docker.com/config/containers/logging/json-file." },
    bootstrapToken: { type: "string", flag: "bootstrap-token", description: "A secret needed for new nodes to join an existing cluster" },
    bootstrapTokenTTL: { type: "string", flag: "bootstrap-token-ttl", description: "How long the bootstrap token is valid for" },
    kubeadmTokenCAHash: { type: "string", flag: "kubeadm-token-ca-hash", description: "Generated during the install script, used for nodes joining (read-only)" },
    useStandardNodePortRange: { type: "boolean" },
    controlPlane: { type: "boolean", flag: "control-plane", description: "Used during a join script to indicate that the node will be an additional master (read-only)" },
    certKey: { type: "string", flag: "cert-key", description: "A secret needed for new master nodes to join an existing cluster (read-only)" },
  },
  required: [ "version" ],
  additionalProperties: false,
};

export interface RKE2Config {
  version: string;
}

export const rke2ConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface K3SConfig {
  version: string;
}

export const k3sConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface DockerConfig {
  version: string;
  s3Override?: string;
  bypassStorageDriverWarnings?: boolean;
  hardFailOnLoopback?: boolean;
  noCEOnEE?: boolean;
  dockerRegistryIP?: string;
  additionalNoProxy?: string;
  noDocker?: boolean;
}

export const dockerConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    bypassStorageDriverWarnings: { type: "boolean" , flag: "bypass-storagedriver-warnings", description: "Force docker to ignore if using devicemapper storage driver in loopback mode" },
    hardFailOnLoopback: { type: "boolean", flag: "hard-fail-on-loopback", description: "The install script stops and exits if it detects a loopback file storage configuration" },
    noCEOnEE: { type: "boolean", flag: "no-ce-on-ee", description: "Do not install Docker-CE on RHEL" },
    dockerRegistryIP: { type: "string", flag: "docker-registry-ip", description: "Used during join scripts, indicates the address of the docker registry (read only)" },
    additionalNoProxy: { type: "string", flag: "additional-no-proxy", description: "This indicates addresses that should not be proxied in addition to the private IP. Multiple addresses can be specified as a comma separated list of IPs or a range of addresses in CIDR notation." },
    noDocker: { type: "boolean", flag: "no-docker", description: "Do not install Docker" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface WeaveConfig {
  version: string;
  s3Override?: string;
  podCIDR?: string;
  podCidrRange?: string;
  IPAllocRange?: string; // deprecated, will be converted to podCidrRange
  encryptNetwork?: boolean; // deprectaed, will be converted to isEncryptionDisabled
  isEncryptionDisabled?: boolean;
  noMasqLocal?: boolean;
}

export const weaveConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    podCIDR: { type: "string", flag: "pod-cidr", description: "The subnet where pods will be found" },
    podCidrRange: { type: "string", flag: "pod-cidr-range", description: "The size of the CIDR where pods can be found" },
    isEncryptionDisabled: { type: "boolean", flag: "disable-weave-encryption", description: "Is encryption in the Weave CNI disabled" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface AntreaConfig {
  version: string;
  s3Override?: string;
  podCIDR?: string;
  podCidrRange?: string;
  isEncryptionDisabled?: boolean;
}

export const antreaConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    podCIDR: { type: "string", description: "The subnet where pods will be found" },
    podCidrRange: { type: "string", description: "The size of the CIDR where pods can be found" },
    isEncryptionDisabled: { type: "boolean", description: "Disable encryption between nodes" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export const calicoConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface FluentdConfig {
  version: string;
  s3Override?: string;
  fullEFKStack?: boolean;
  efkStack?: boolean;
}

export interface RookConfig {
  version: string;
  s3Override?: string;
  storageClass?: string; // deprecated, will be converted to storageClassName
  cephPoolReplicas?: number; // deprecated, will be converted to cephReplicaCount
  cephReplicaCount?: number;
  storageClassName?: string;
  isBlockStorageEnabled?: boolean;
  isSharedFilesystemDisabled?: boolean;
  blockDeviceFilter?: string;
  bypassUpgradeWarning?: boolean;
  hostpathRequiresPrivileged?: boolean;
}

export const rookConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    storageClassName: { type: "string", flag: "storage-class-name", description: "The name of the StorageClass used by rook" },
    cephReplicaCount: { type: "number", flag: "ceph-replica-count", description: "The number of replicas in the Rook Ceph pool" },
    isBlockStorageEnabled: { type: "boolean", flag: "rook-block-storage-enabled", description: "Use block devices instead of the filesystem for storage in the Ceph cluster" },
    isSharedFilesystemDisabled: { type: "boolean", flag: "rook-shared-filesystem-disabled", description: "Disable the rook-ceph shared filesystem" },
    blockDeviceFilter: { type: "string", flag: "rook-block-device-filter", description: "Only use block devices matching this regex" },
    bypassUpgradeWarning: { type: "boolean", flag: "rook-bypass-upgrade-warning", description: "Bypass upgrade warning prompt" },
    hostpathRequiresPrivileged: { type: "boolean", flag: "rook-hostpath-requires-privileged", description: "Runs Ceph Pods as privileged to be able to write to hostPaths in OpenShift with SELinux restrictions" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface OpenEBSConfig {
  version: string;
  s3Override?: string;
  namespace?: string;
  isLocalPVEnabled?: boolean;
  localPVStorageClassName?: string;
  isCstorEnabled?: boolean;
  cstorStorageClassName?: string;
}

export const openEBSConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    namespace: { type: "string", flag: "openebs-namespace", description: "The namespace Open EBS is installed to" },
    isLocalPVEnabled: { type: "boolean", flag: "openebs-localpv-enabled", description: "Turn on localPV storage provisioning" },
    localPVStorageClassName: { type: "string", flag: "openebs-localpv-storage-class-name", description: "StorageClass name for local PV provisioner (Name it “default” to make it the cluster’s default provisioner)" },
    isCstorEnabled: { type: "boolean", flag: "openebs-cstor-enabled", description: "Turn on cstor storage provisioning" },
    cstorStorageClassName: { type: "string", flag: "openebs-cstor-storage-class-name", description: "The StorageClass name for cstor provisioner (Name it “default” to make it the cluster’s default provisioner)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface MinioConfig {
  version: string;
  s3Override?: string;
  namespace?: string;
  hostPath?: string;
  claimSize?: string;
}

export const minioConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    namespace: { type: "string", flag: "minio-namespace", description: "The namespace Minio is installed to" },
    hostPath: { type: "string", flag: "minio-hostpath", description: "Configure the minio deployment to use a local hostPath for storing data." },
    claimSize: { type: "string", flag: "claim-size", description: "Configure the size of the Persistent Volume Claim that Minio will use, defaulting to 10Gi" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface ContourConfig {
  version: string;
  s3Override?: string;
  tlsMinimumProtocolVersion?: string;
  httpPort?: number;
  httpsPort?: number;
}

export const contourConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    tlsMinimumProtocolVersion: { type: "string", flag: "contour-tls-minimum-protocol-version", description: "The minimum TLS protocol version that is allowed (default 1.2)." },
    httpPort: { type: "number", flag: "contour-http-port", description: "Sets the NodePort used for http traffic on ingress routes." },
    httpsPort: { type: "number", flag: "contour-https-port", description: "Sets the NodePort used for https (TLS) traffic on ingress routes." },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface RegistryConfig {
  version: string;
  s3Override?: string;
  publishPort?: number;
}

export const registryConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    publishPort: { type: "number", flag: "registry-publish-port", description: "add a NodePort service to the registry" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface PrometheusConfig {
  version: string;
  s3Override?: string;
  serviceType?: string;
}

export const prometheusConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    serviceType: { type: "string", flag: "service-type", description: "Change the service type used to expose Prometheus, Alertmanager and Grafana, defaulting to NodePort." },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface CalicoConfig {
  version: string;
  s3Override?: string;
}

export const fluentdConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    fullEFKStack : { type: "boolean", flag: "fluentd-full-efk-stack", description: "Install ElasticSearch and Kibana in addition to Fluentd" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface KotsadmConfig {
  version: string;
  s3Override?: string;
  disableS3?: boolean;
  applicationSlug?: string;
  uiBindPort?: number;
  hostname?: string;
  applicationNamespace?: string;
}

export const kotsadmConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    disableS3: { type: "boolean", flag: "disable-s3", description: "Migrate application archives and support bundles from S3 and use a local volume in the kotsadm statefulset instead. The migration process is irreversible and will replace the kotsadm deployment with a statefulset. Defaults to 'false'" },
    applicationSlug: { type: "string", flag: "kotsadm-application-slug", description: "The slug shown on the app settings page of vendor web" },
    uiBindPort: { type: "number", flag: "kotsadm-ui-bind-port", description: "This is the port where the kots admin panel can be interacted with via browser" },
    hostname: { type: "string", flag: "kotsadm-hostname", description: "The hostname that the admin console will be exposed on" },
    applicationNamespace: { type: "string", flag: "kotsadm-application-namespaces", description: "An additional namespace that should be pre-created during the install (For applications that install to other namespaces outside of the one where kotsadm is running)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface VeleroConfig {
  version: string;
  s3Override?: string;
  namespace?: string;
  disableCLI?: boolean;
  disableRestic?: boolean;
  localBucket?: string;
  resticRequiresPrivileged?: boolean;
}

export const veleroConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    namespace: { type: "string", flag: "velero-namespace", description: "The namespace to install velero into if not using the default"},
    disableCLI: { type: "boolean", flag: "velero-disable-cli", description: "Don't install the velero CLI on the host" },
    disableRestic: { type: "boolean", flag: "velero-disable-restic", description: "Don’t install the restic integration" },
    localBucket: { type: "string", flag : "velero-local-bucket", description: "Name of the bucket to create snapshots in the local object store"},
    resticRequiresPrivileged: { type: "boolean", flag: "velero-restic-requires-privileged", description: "Runs Restic container in privileged mode" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface EkcoConfig {
  version: string;
  s3Override?: string;
  nodeUnreachableToleration?: string;
  minReadyMasterNodeCount?: number;
  minReadyWorkerNodeCount?: number;
  shouldDisableRebootService?: boolean;
  shouldDisableClearNodes?: boolean;
  shouldEnablePurgeNodes?: boolean;
  rookShouldUseAllNodes?: boolean;
  podImageOverrides?: Array<string>;
}

export const ekcoConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    nodeUnreachableToleration: { type: "string", flag: "ekco-node-unreachable-toleration-duration" , description: "How long a Node must have status unreachable before it’s purged" },
    minReadyMasterNodeCount: { type: "number", flag: "ekco-min-ready-master-node-count" , description: "Ekco will not purge a master node if it would result in less than this many masters remaining" },
    minReadyWorkerNodeCount: { type: "number", flag: "ekco-min-ready-worker-node-count" , description: "Ekco will not purge a worker node if it would result in less than this many workers remaining" },
    shouldDisableRebootService: { type: "boolean", flag: "ekco-should-disable-reboot-service" , description: "Do not install the systemd shutdown service that cordons a node and deletes pods with PVC and Shared FS volumes mounted" },
    shouldDisableClearNodes: { type: "boolean", description: "Do not watch for unreachable nodes and force delete pods on them stuck in the terminating state" },
    shouldEnablePurgeNodes: { type: "boolean", description: "Watch for unreachable nodes and automatically remove them from the cluster" },
    rookShouldUseAllNodes: { type: "boolean", flag: "ekco-rook-should-use-all-nodes" , description: "This will disable management of nodes in the CephCluster resource. If false, ekco will add nodes to the storage list and remove them when a node is purged" },
    podImageOverrides: { type: "array", items: { type: "string" }, flag: "pod-image-overrides", description: "Switch images in a pod when created" },
  },
  required: ["version"],
  // additionalProperties: false,
};

export interface KurlConfig {
  additionalNoProxyAddresses: string[];
  airgap?: boolean;
  hostnameCheck?: string;
  ignoreRemoteLoadImagesPrompt?: boolean;
  ignoreRemoteUpgradePrompt?: boolean;
  hostPreflights?: object;
  licenseURL?: string;
  nameserver?: string;
  noProxy?: string;
  privateAddress?: string;
  preflightIgnore?: boolean;
  preflightIgnoreWarnings?: boolean;
  proxyAddress?: string;
  publicAddress?: string;
  bypassFirewalldWarning?: boolean; // this is not in the installer crd
  hardFailOnFirewalld?: boolean; // this is not in the installer crd
  task?: string; // this is not in the installer crd
  installerVersion?: string;
}

export const kurlConfigSchema = {
  type: "object",
  properties: {
    additionalNoProxyAddresses: { type: "array", items: { type: "string" }, description: "Addresses that can be reached without a proxy" },
    airgap: { type: "boolean", flag: "airgap", description: "Indicates if this install is an airgap install" },
    hostnameCheck: { type: "string", flag: "hostname-check" , description: "Used as a check during an upgrade to ensure the script will run only on the given hostname" },
    hostPreflights: { type: "object", description: "Used to add additional host preflight checks."},
    ignoreRemoteLoadImagesPrompt: { type: "boolean", flag: "ignore-remote-load-images-prompt" , description: "Bypass prompt to load images on remotes. This is useful for automating upgrades." },
    ignoreRemoteUpgradePrompt: { type: "boolean", flag: "ignore-remote-upgrade-prompt" , description: "Bypass prompt to upgrade remotes. This is useful for automating upgrades." },
    licenseURL: { type: "string", description: "A URL to a licensing agreement that will presented during installation and needs to be accepted or the install will exit." },
    nameserver: { type: "string" },
    noProxy: { type: "boolean", flag: "no-proxy" , description: "Don’t detect or configure a proxy" },
    preflightIgnore: { type: "boolean", flag: "preflight-ignore" , description: "Ignore preflight failures and warnings" },
    preflightIgnoreWarnings: { type: "boolean", flag: "preflight-ignore-warnings" , description: "Ignore preflight warnings" },
    privateAddress: { type: "string", flag: "private-address" , description: "The local address of the host (different for each host in the cluster)" },
    proxyAddress: { type: "string", flag: "http-proxy" , description: "The address of the proxy to use for outbound connections" },
    publicAddress: { type: "string", flag: "public-address" , description: "The public address of the host (different for each host in the cluster), will be added as a CNAME to the k8s API server cert so you can use kubectl with this address" },
    bypassFirewalldWarning: { type: "boolean", flag: "bypass-firewalld-warning" , description: "Continue installing even if the firewalld service is active" },
    hardFailOnFirewalld: { type: "boolean", flag: "hard-fail-on-firewalld" , description: "Exit the install script if the firewalld service is active" },
    installerVersion: { type: "string", description: "The upstream version of kURL to use as part of the installation - see https://kurl.sh/docs/install-with-kurl/#versioned-releases" },
  },
  additionalProperties: false,
};

export interface ContainerdConfig {
  version: string;
  s3Override?: string;
}

export const containerdConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    tomlConfig: { type: "string" },
    preserveConfig: { type: "boolean" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface CollectdConfig {
  version: string;
  s3Override?: string;
}

export const collectdConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface IptablesConfig {
  iptablesCmds?: string[][];
  preserveConfig?: boolean;
}

export interface CertManagerConfig {
  version: string;
  s3Override?: string;
}

export const certManagerSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface MetricsServerConfig {
  version: string;
  s3Override?: string;
}

export const metricsServerSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export const iptablesConfigSchema = {
  type: "object",
  properties: {
    iptablesCmds: {
      type: "array",
      items: {
        type: "array",
        items: {
          type: "string",
        },
      },
    },
    preserveConfig: { type: "boolean" },
    additionalProperties: false,
  },
};

export interface FirewalldConfig {
  bypassFirewalldWarning?: boolean;
  disableFirewalld?: boolean;
  firewalld?: string;
  firewalldCmds?: string[][];
  hardFailOnFirewalld?: boolean;
  preserveConfig?: boolean;
}

export const firewalldConfigSchema = {
  type: "object",
  properties: {
    bypassFirewalldWarning: { type: "boolean" },
    disableFirewalld: { type: "boolean" },
    firewalld: { type: "string" },
    firewalldCmds: {
      type: "array",
      items: {
        type: "array",
        items: {
          type: "string",
        },
      },
    },
    hardFailOnFirewalld: { type: "boolean" },
    preserveConfig: { type: "boolean" },
  },
};

export interface SelinuxConfig {
  chconCmds?: string[][];
  disableSelinux?: boolean;
  preserveConfig?: boolean;
  selinux?: string;
  semanageCmds?: string[][];
  type?: string;
}

export const selinuxConfigSchema = {
  type: "object",
  properties: {
    chconCmds: {
      type: "array",
      items: {
        type: "array",
        items: {
          type: "string",
        },
      },
    },
    disableSelinux: { type: "boolean" },
    preserveConfig: { type: "boolean" },
    selinux: { type: "string" },
    semanageCmds: {
      type: "array",
      items: {
        type: "array",
        items: {
          type: "string",
        },
      },
    },
  },
};

export interface HelmConfig {
  helmfileSpec: string;
  additionalImages?: string[];
}

export const helmConfigSchema = {
  type: "object",
  properties: {
    helmfileSpec: { type: "string", flag: "helmfile-spec", description: "Helmfile specification contents to be synced with the cluster"},
    additionalImages: { type: "array", items: { type: "string" }, description: "Additional images to be included in the airgap bundle - useful for installing operators" },
  },
  required: ["helmfileSpec"],
  additionalProperties: false,
};

export interface LonghornConfig {
  s3Override?: string;
  uiBindPort?: number;
  uiReplicaCount?: number;
  version: string;
}

export const LonghornSchema = {
  type: "object",
  properties: {
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
    uiBindPort: { type: "number", flag: "longhorn-ui-bind-port", description: "This is the port where the Longhorn UI can be reached via the browser" },
    uiReplicaCount: { type: "number", flag: "longhorn-ui-replica-count", description: "The number of pods to deploy for the Longhorn UI (default is 0)" },
    version: { type: "string" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface SonobuoyConfig {
  version: string;
  s3Override?: string;
}

export const sonobuoySchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface UFWConfig {
  bypassUFWWarning?: boolean;
  disableUFW?: boolean;
  hardFailOnUFW?: boolean;
}

export const ufwConfigSchema = {
  type: "object",
  properties: {
    bypassUFWWarning: { type: "boolean" },
    disableUFW: { type: "boolean" },
    hardFailOnUFW: { type: "boolean" },
  },
};

export interface GoldpingerConfig {
  version: string;
  s3Override?: string;
}

export const goldpingerSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    s3Override: { type: "string", flag: "s3-override", description: "Override the download location for addon package distribution (used for CI/CD testing alpha addons)" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface InstallerSpec {
  kubernetes: KubernetesConfig;
  rke2?: RKE2Config;
  k3s?: K3SConfig;
  docker?: DockerConfig;
  weave?: WeaveConfig;
  antrea?: AntreaConfig;
  calico?: CalicoConfig;
  rook?: RookConfig;
  openebs?: OpenEBSConfig;
  minio?: MinioConfig;
  contour?: ContourConfig;
  registry?: RegistryConfig;
  prometheus?: PrometheusConfig;
  fluentd?: FluentdConfig;
  kotsadm?: KotsadmConfig;
  velero?: VeleroConfig;
  ekco?: EkcoConfig;
  kurl?: KurlConfig;
  containerd?: ContainerdConfig;
  collectd?: CollectdConfig;
  certManager?: CertManagerConfig;
  metricsServer?: MetricsServerConfig;
  iptablesConfig?: IptablesConfig;
  firewalldConfig?: FirewalldConfig;
  selinuxConfig?: SelinuxConfig;
  helm?: HelmConfig;
  longhorn?: LonghornConfig;
  sonobuoy?: SonobuoyConfig;
  ufw?: UFWConfig;
  goldpinger?: GoldpingerConfig;
}

const specSchema = {
  type: "object",
  properties: {
    // order here determines order in rendered yaml
    kubernetes: kubernetesConfigSchema,
    rke2: rke2ConfigSchema,
    k3s: k3sConfigSchema,
    docker: dockerConfigSchema,
    weave: weaveConfigSchema,
    antrea: antreaConfigSchema,
    calico: calicoConfigSchema,
    rook: rookConfigSchema,
    openebs: openEBSConfigSchema,
    minio: minioConfigSchema,
    contour: contourConfigSchema,
    registry: registryConfigSchema,
    prometheus: prometheusConfigSchema,
    fluentd: fluentdConfigSchema,
    kotsadm: kotsadmConfigSchema,
    velero: veleroConfigSchema,
    ekco: ekcoConfigSchema,
    kurl: kurlConfigSchema,
    containerd: containerdConfigSchema,
    collectd: collectdConfigSchema,
    certManager: certManagerSchema,
    metricsServer: metricsServerSchema,
    firewalldConfig: firewalldConfigSchema,
    iptablesConfig: iptablesConfigSchema,
    selinuxConfig: selinuxConfigSchema,
    helm: helmConfigSchema,
    longhorn: LonghornSchema,
    sonobuoy: sonobuoySchema,
    ufw: ufwConfigSchema,
    goldpinger: goldpingerSchema,
  },
  additionalProperites: false,
};

export interface ObjectMeta {
  name: string;
}

export interface InstallerObject {
  apiVersion: string;
  kind: string;
  metadata: ObjectMeta;
  spec: InstallerSpec;
}

export class Installer {

  public static latest(): Installer {
    const i = new Installer();

    i.id = "latest";
    i.spec.kubernetes = { version: "latest" };
    i.spec.containerd = { version: "latest" };
    i.spec.weave = { version: "latest" };
    i.spec.longhorn = { version: "latest"};
    i.spec.minio = { version: "latest"};
    i.spec.ekco = { version: "latest" };
    i.spec.contour = { version: "latest" };
    i.spec.registry = { version: "latest" };
    i.spec.prometheus = { version: "latest" };

    return i;
  }

  // Return an ordered list of all addon fields in the spec.
  public static specPaths(): string[] {
    const paths: string[] = [];

    _.each(specSchema.properties, (configSchema, configName) => {
      _.each(configSchema.properties, (val, field) => {
        paths.push(`${configName}.${field}`);
      });
    });

    return paths;
  }

  // returned installer must be validated before use
  public static parse(doc: string, teamID?: string): Installer {
    const parsed = yaml.load(doc);

    const i = new Installer(teamID);
    i.id = _.get(parsed, "metadata.name", "");

    if (!_.isPlainObject(parsed)) {
      return i;
    }

    if (!parsed.spec || !_.isPlainObject(parsed.spec)) {
      return i;
    }
    i.spec = parsed.spec;

    const modified = i.legacyFieldConversion();

    if (modified.spec.collectd && modified.spec.collectd.version === "0.0.1") {
      modified.spec.collectd.version = "v5";
    }

    if (parsed.apiVersion === "kurl.sh/v1beta1") {
      return modified.migrateV1Beta1();
    }

    return modified;
  }

  public legacyFieldConversion(): Installer {
   // this function is to ensure that old flags get converted to new befoore the hash get computed
   // and the installer object is stored. if both flags are present, the old is ignored and removed

    const i = this.clone();

    if (i.spec.weave !== undefined) {
        if (i.spec.weave.encryptNetwork !== undefined && i.spec.weave.isEncryptionDisabled === undefined) {
          if (i.spec.weave.encryptNetwork === true) {
              i.spec.weave.isEncryptionDisabled = false;
          } else {
              i.spec.weave.isEncryptionDisabled = true;
          }
        }
        if (i.spec.weave.encryptNetwork !== undefined) {
            delete i.spec.weave.encryptNetwork;
        }
    }

    if (_.get(i.spec, "fluentd.efkStack")) {
        if (i.spec.fluentd) {
          if (i.spec.fluentd.efkStack && !i.spec.fluentd.fullEFKStack) {
              i.spec.fluentd.fullEFKStack = i.spec.fluentd.efkStack;
          }
          delete i.spec.fluentd.efkStack;
        }
    }

    if (_.get(i.spec, "weave.IPAllocRange")) {
        if (i.spec.weave) {
          if (i.spec.weave.IPAllocRange && !i.spec.weave.podCidrRange) {
              i.spec.weave.podCidrRange = i.spec.weave.IPAllocRange;
          }
          delete i.spec.weave.IPAllocRange;
        }
    }

    if (_.get(i.spec, "rook.storageClass")) {
        if (i.spec.rook) {
          if (i.spec.rook.storageClass && !i.spec.rook.storageClassName) {
              i.spec.rook.storageClassName = i.spec.rook.storageClass;
          }
          delete i.spec.rook.storageClass;
        }
    }

    if (_.get(i.spec, "rook.cephPoolReplicas")) {
        if (i.spec.rook) {
          if (i.spec.rook.cephPoolReplicas && !i.spec.rook.cephReplicaCount) {
              i.spec.rook.cephReplicaCount = i.spec.rook.cephPoolReplicas;
          }
          delete i.spec.rook.cephPoolReplicas;
        }
    }

    return i;
  }

  public static async hasVersion(config: string, version: string, kurlVersion?: string): Promise<boolean> {
    if (version === "latest") {
      return true;
    }

    const distUrl = getDistUrl();

    const installerversions = await getInstallerVersions(distUrl, kurlVersion);

    version = await Installer.resolveVersion(config, version);

    if (kurlVersion) {
      // hit s3 to determine if this addon+version exists for the specified installer version
      // NOTE: this is no longer necessary since getInstallerVersions uses supported-versions-gen.json
      const generatedURL = getPackageUrl(getDistUrl(), kurlVersion, `${Installer.generatePackageName(config, version)}.tar.gz`);

      const resp = await fetch(generatedURL, {method:"HEAD"});
      return resp.ok;
    }

    if (_.includes(installerversions[config], version)) {
      return true;
    }
    return false;
  }

  // replace problematic versions that do not sort because of semver pre-release
  private static replaceVersions = {
    "rook": {"1.0.4": "1.0.4-0.0.0"},
    "prometheus": {"0.46.0": "0.46.0-0.0.0"},
  };

  public static async resolveVersion(config: string, version: string, kurlVersion?: string): Promise<string> {
    const distUrl = getDistUrl();

    const installerversions = await getInstallerVersions(distUrl, kurlVersion);

    if (version === "latest") {
      return _.first(installerversions[config]) || "latest";
    }
    if (!version.endsWith(".x")) {
      return version
    }

    let addonInstallerVersions = installerversions[config] || [];

    if (config in Installer.replaceVersions) {
      Object.keys(Installer.replaceVersions[config]).forEach((k: string) => {
        addonInstallerVersions = addonInstallerVersions.map(function(version: string): string {
          return version === k ? Installer.replaceVersions[config][k] : version;
        });
      });
    }

    let match = Installer.resolveLatestPatchVersion(version, addonInstallerVersions);
    if (config in Installer.replaceVersions) {
      Object.keys(Installer.replaceVersions[config]).some((k: string) => {
        if (match === Installer.replaceVersions[config][k]) {
          match = k;
          return true;
        }
        return false;
      });
    }
    return match;
  }

  public static isSHA(id: string): boolean {
    return /^[0-9a-f]{7}$/.test(id);
  }

  public static isValidSlug(id: string): boolean {
    return /^[0-9a-zA-Z-_]{1,255}$/.test(id);
  }

  public static slugIsReserved(id: string): boolean {
    return _.includes([
      "latest",
      "beta",
      "stable",
      "unstable",
      "healthz",
      "dist",
      "installer",
      "bundle",
      "versions",
    ], _.lowerCase(id));
  }

  public static isValidCidrRange(range: string): boolean {
    const i = parseInt(range.replace(/^\//, ""), 10);
    return !isNaN(i) && i > 0 && i <= 32;
  }

  public id: string;
  public spec: InstallerSpec;

  constructor(
    public readonly teamID?: string,
  ) {
    this.spec = {
      kubernetes: { version: "" },
    };
  }

  public clone(): Installer {
    const i = new Installer(this.teamID);

    i.id = this.id;
    i.spec = _.cloneDeep(this.spec);

    return i;
  }

  // Going forward new fields are automatically included in the hash after being sorted
  // alphabetically but the arbitrary order must be preserved for legacy fields.
  public hash(): string {
    const h = crypto.createHash("sha256");

    if (this.spec.kubernetes && this.spec.kubernetes.version) {
      h.update(`kubernetes_version=${this.spec.kubernetes.version}`);
    }
    if (this.spec.weave && this.spec.weave.version) {
      h.update(`weave_version=${this.spec.weave.version}`);
    }
    if (this.spec.rook && this.spec.rook.version) {
      h.update(`rook_version=${this.spec.rook.version}`);
    }
    if (this.spec.contour && this.spec.contour.version) {
      h.update(`contour_version=${this.spec.contour.version}`);
    }
    if (this.spec.registry && this.spec.registry.version) {
      h.update(`registry_version=${this.spec.registry.version}`);
    }
    if (this.spec.prometheus && this.spec.prometheus.version) {
      h.update(`prometheus_version=${this.spec.prometheus.version}`);
    }
    if (this.spec.kotsadm && this.spec.kotsadm.version) {
      h.update(`kotsadm_version=${this.spec.kotsadm.version}`);
    }
    if (this.spec.kotsadm && this.spec.kotsadm.applicationSlug) {
      h.update(`kotsadm_applicationSlug=${this.spec.kotsadm.applicationSlug}`);
    }

    const legacy = {
      kubernetes_version: true,
      weave_version: true,
      rook_version: true,
      contour_version: true,
      registry_version: true,
      prometheus_version: true,
      kotsadm_version: true,
      kotsadm_applicationSlug: true,
    };
    const fields: string[] = [];
    _.each(_.keys(this.spec), (config) => {
      _.each(_.keys(this.spec[config]), (field) => {
        const val = this.spec[config][field];
        const fieldKey = `${config}_${field}`;

        if (_.isUndefined(val)) {
          return;
        }
        if (legacy[fieldKey]) {
          return;
        }

        fields.push(`${fieldKey}=${val}`);
      });
    });

    _.each(fields.sort(), (field) => {
      h.update(field);
    });

    return h.digest("hex").substring(0, 7);
  }

  // kurl.sh/v1beta1 originally had the addon name with an empty version to indicate the addon was
  // disabled. Now a disabled addon does not appear at all in the yaml spec. We changed this without
  // changing the apiVersion but we can detect the old style of config with no version and delete
  // the whole addon config. This is not necessary for new addons added after kotsadm.
  public migrateV1Beta1(): Installer {
    const i = this.clone();

    if (!_.get(i.spec, "docker.version")) {
      delete i.spec.docker;
    }
    if (!_.get(i.spec, "weave.version")) {
      delete i.spec.weave;
    }
    if (!_.get(i.spec, "rook.version")) {
      delete i.spec.rook;
    }
    if (!_.get(i.spec, "contour.version")) {
      delete i.spec.contour;
    }
    if (!_.get(i.spec, "registry.version")) {
      delete i.spec.registry;
    }
    if (!_.get(i.spec, "prometheus.version")) {
      delete i.spec.prometheus;
    }
    if (!_.get(i.spec, "kotsadm.version")) {
      delete i.spec.kotsadm;
    }

    return i;
  }

  public toYAML(): string {
    return yaml.dump(this.toObject());
  }

  public toObject(): InstallerObject {
    const obj: InstallerObject = {
      apiVersion: "cluster.kurl.sh/v1beta1",
      kind: "Installer",
      metadata: {
        name: `${this.id}`,
      },
      spec: {} as InstallerSpec,
    };
    if (this.spec.kubernetes) {
      obj.spec.kubernetes = _.cloneDeep(this.spec.kubernetes);
    }

    // add spec properties in order they should be rendered in yaml
    _.each(specSchema.properties, (val, key) => {
      if (this.spec[key]) {
        obj.spec[key] = _.cloneDeep(this.spec[key]);
      }
    });

    return obj;
  }

  public async resolve(): Promise<Installer> {
    const i = this.clone();

    await Promise.all(_.each(_.keys(i.spec), async (config: string) => {
      if (i.spec[config].version) {
        i.spec[config].version = await Installer.resolveVersion(config, i.spec[config].version);
      }
    }));

    return i;
  }

  public async validate(): Promise<ErrorResponse | undefined> {
    if (!this.spec ||
      (
        (!this.spec.kubernetes || !this.spec.kubernetes.version) &&
        (!this.spec.rke2 || !this.spec.rke2.version) &&
        (!this.spec.k3s || !this.spec.k3s.version)
      )
    ) {
      return {error: {message: "Kubernetes version is required"}};
    }

    const ajv = new Ajv({
      strict: false,
    });
    const validate = ajv.compile(specSchema);
    const valid = validate(this.spec);

    if (!valid && validate.errors && validate.errors.length) {
      const err = validate.errors[0];
      const message = `spec${err.instancePath} ${err.message}`;
      return {error: {message}};
    }

    let installerVersion: string|undefined;
    if (this.spec.kurl) {
      installerVersion = this.spec.kurl.installerVersion;
    }

    if (this.spec.kubernetes) {
      if (!(await Installer.hasVersion("kubernetes", this.spec.kubernetes.version, installerVersion)) && !this.hasS3Override("kubernetes")) {
        return {error: {message: `Kubernetes version ${_.escape(this.spec.kubernetes.version)} is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
      }
      if (this.spec.kubernetes.serviceCidrRange && !Installer.isValidCidrRange(this.spec.kubernetes.serviceCidrRange)) {
        return {error: {message: `Kubernetes serviceCidrRange "${_.escape(this.spec.kubernetes.serviceCidrRange)}" is invalid`}};
      }
    }
    if (this.spec.rke2) {
      if (!(await Installer.hasVersion("rke2", this.spec.rke2.version, installerVersion)) && !this.hasS3Override("rke2")) {
        return {error: {message: `RKE2 version ${_.escape(this.spec.rke2.version)} is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
      }
    }
    if (this.spec.kubernetes && this.spec.rke2) {
      return {error: {message: `This spec contains both kubeadm and rke2, please specifiy only one Kubernetes distribution`}};
    }
    if (this.spec.k3s) {
      if (!(await Installer.hasVersion("k3s", this.spec.k3s.version, installerVersion)) && !this.hasS3Override("k3s")) {
        return {error: {message: `K3S version ${_.escape(this.spec.k3s.version)} is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
      }
    }
    if (this.spec.kubernetes && this.spec.k3s) {
      return {error: {message: `This spec contains both kubeadm and k3s, please specifiy only one Kubernetes distribution`}};
    }
    if (this.spec.weave && !(await Installer.hasVersion("weave", this.spec.weave.version, installerVersion)) && !this.hasS3Override("weave")) {
      return {error: {message: `Weave version "${_.escape(this.spec.weave.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.weave && this.spec.weave.podCidrRange && !Installer.isValidCidrRange(this.spec.weave.podCidrRange)) {
      return {error: {message: `Weave podCidrRange "${_.escape(this.spec.weave.podCidrRange)}" is invalid`}};
    }
    if (this.spec.antrea && !(await Installer.hasVersion("antrea", this.spec.antrea.version, installerVersion)) && !this.hasS3Override("antrea")) {
      return {error: {message: `Antrea version "${_.escape(this.spec.antrea.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.antrea && this.spec.antrea.podCidrRange && !Installer.isValidCidrRange(this.spec.antrea.podCidrRange)) {
      return {error: {message: `Antrea podCidrRange "${_.escape(this.spec.antrea.podCidrRange)}" is invalid`}};
    }
    if (this.spec.rook && !(await Installer.hasVersion("rook", this.spec.rook.version, installerVersion)) && !this.hasS3Override("rook")) {
      return {error: {message: `Rook version "${_.escape(this.spec.rook.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.contour && !(await Installer.hasVersion("contour", this.spec.contour.version, installerVersion)) && !this.hasS3Override("contour")) {
      return {error: {message: `Contour version "${_.escape(this.spec.contour.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.registry && !(await Installer.hasVersion("registry", this.spec.registry.version, installerVersion)) && !this.hasS3Override("registry")) {
      return {error: {message: `Registry version "${_.escape(this.spec.registry.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.prometheus && !(await Installer.hasVersion("prometheus", this.spec.prometheus.version, installerVersion)) && !this.hasS3Override("prometheus")) {
      return {error: {message: `Prometheus version "${_.escape(this.spec.prometheus.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.fluentd && !(await Installer.hasVersion("fluentd", this.spec.fluentd.version, installerVersion)) && !this.hasS3Override("fluentd")) {
      return {error: {message: `Fluentd version "${_.escape(this.spec.fluentd.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.kotsadm) {
      if (!(await Installer.hasVersion("kotsadm", this.spec.kotsadm.version, installerVersion)) && !this.hasS3Override("kotsadm")) {
        return {error: {message: `Kotsadm version "${_.escape(this.spec.kotsadm.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
      }
    }
    if (this.spec.velero && !(await Installer.hasVersion("velero", this.spec.velero.version, installerVersion)) && !this.hasS3Override("velero")) {
      return {error: {message: `Velero version "${_.escape(this.spec.velero.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.openebs && !(await Installer.hasVersion("openebs", this.spec.openebs.version, installerVersion)) && !this.hasS3Override("openebs")) {
      return {error: {message: `OpenEBS version "${_.escape(this.spec.openebs.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.minio && !(await Installer.hasVersion("minio", this.spec.minio.version, installerVersion)) && !this.hasS3Override("minio")) {
      return {error: {message: `Minio version "${_.escape(this.spec.minio.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.ekco && !(await Installer.hasVersion("ekco", this.spec.ekco.version, installerVersion)) && !this.hasS3Override("ekco")) {
      return {error: {message: `Ekco version "${_.escape(this.spec.ekco.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.containerd && !(await Installer.hasVersion("containerd", this.spec.containerd.version, installerVersion)) && !this.hasS3Override("containerd")) {
      return {error: {message: `Containerd version "${_.escape(this.spec.containerd.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.containerd && this.spec.docker) {
      return {error: {message: `This spec contains both docker and containerd, please specifiy only one CRI`}};
    }
    if (this.spec.collectd && !(await Installer.hasVersion("collectd", this.spec.collectd.version, installerVersion)) && !this.hasS3Override("collectd")) {
      return {error: {message: `Collectd version "${_.escape(this.spec.collectd.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.certManager && !(await Installer.hasVersion("certManager", this.spec.certManager.version, installerVersion)) && !this.hasS3Override("certManager")) {
      return {error: {message: `CertManager version "${_.escape(this.spec.certManager.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.metricsServer && !(await Installer.hasVersion("metricsServer", this.spec.metricsServer.version, installerVersion)) && !this.hasS3Override("metricsServer")) {
      return {error: {message: `MetricsServer version "${_.escape(this.spec.metricsServer.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.longhorn && !(await Installer.hasVersion("longhorn", this.spec.longhorn.version, installerVersion)) && !this.hasS3Override("longhorn")) {
      return {error: {message: `Longhorn version "${_.escape(this.spec.longhorn.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.sonobuoy && !(await Installer.hasVersion("sonobuoy", this.spec.sonobuoy.version, installerVersion)) && !this.hasS3Override("sonobuoy")) {
      return {error: {message: `Sonobuoy version "${_.escape(this.spec.sonobuoy.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    if (this.spec.goldpinger && !(await Installer.hasVersion("goldpinger", this.spec.goldpinger.version, installerVersion)) && !this.hasS3Override("goldpinger")) {
      return {error: {message: `Goldpinger version "${_.escape(this.spec.goldpinger.version)}" is not supported${installerVersion ? " for installer version " + _.escape(installerVersion) : ""}`}};
    }
    // Rook 1.0.4. is incompatible with Kubernetes 1.20+
    if (this.spec.rook && this.spec.rook.version === "1.0.4") {
      if (this.spec.kubernetes && semver.gte(this.spec.kubernetes.version, "1.20.0")) {
        return {error: {message: "Rook 1.0.4 is not compatible with Kubernetes 1.20+"}};
      }
    }

    if (this.spec.prometheus && this.spec.prometheus.version && this.spec.prometheus.serviceType) {
      if (this.spec.prometheus.serviceType != "" && this.spec.prometheus.serviceType != "ClusterIP" && this.spec.prometheus.serviceType != "NodePort") {
        return {error: {message: `Supported Prometheus service types are "NodePort" and "ClusterIP", not "${this.spec.prometheus.serviceType}"`}};
      }

      const installerVersions = await getInstallerVersions(getDistUrl(), installerVersion);

      if (installerVersions.prometheus.indexOf(this.spec.prometheus.version) != -1 &&
        installerVersions.prometheus.indexOf(this.spec.prometheus.version) > installerVersions.prometheus.indexOf("0.48.1-16.10.0")) {
        return {error: {message: `Prometheus service types are supported for version "0.48.1-16.10.0" and later, not "${this.spec.prometheus.version}"`}};
      }
    }
  }

  public static generatePackageName(config: string, version: string): string {
    const special = /[+]/g;
    return `${_.kebabCase(config)}-${version.replace(special, "-")}` // replace special characters
  }

  public async packages(kurlVersion?: string): Promise<string[]> {
    if (!kurlVersion && this.spec.kurl) {
      kurlVersion = this.spec.kurl.installerVersion;
    }
    let binUtils = String(process.env["KURL_BIN_UTILS_FILE"] || "kurl-bin-utils-latest.tar.gz").slice(0, -7); // remove .tar.gz
    if (kurlVersion) {
      binUtils = `kurl-bin-utils-${kurlVersion}`
    }
    const pkgs = [ "common", binUtils, "host-openssl" ];
    if (this.spec.longhorn) {
      pkgs.push("host-longhorn");
    }

    let kubernetesVersion = "";
    await Promise.all(_.each(_.keys(this.spec), async (config: string) => {
      const version = this.spec[config].version;
      if (version) {
        pkgs.push(Installer.generatePackageName(config, this.spec[config].version));

        const installerVersions = await getInstallerVersions(getDistUrl(), kurlVersion);

        // include an extra version of kubernetes so they can upgrade 2 minor versions
        if (config === "kubernetes") {
          kubernetesVersion = version;
          const prevMinor = semver.minor(version) - 1;
          const step = Installer.latestMinors(installerVersions[config])[prevMinor];
          if (step !== "0.0.0") {
            pkgs.push(`${config}-${step}`);
          }
        } else if (config === "rke2") {
          kubernetesVersion = version.replace(/^v?([^-+]+).*$/, '$1');
        } else if (config === "k3s") {
          kubernetesVersion = version.replace(/^v?([^-+]+).*$/, '$1');
        }
      }
    }));

    // include conformance package if sonobuoy and kubernetes
    // we only build conformance packages for 1.17.0+
    if (kubernetesVersion && semver.gte(kubernetesVersion, "1.17.0") && _.get(this.spec, "sonobuoy.version")) {
      pkgs.push(`kubernetes-conformance-${kubernetesVersion}`);
    }

    return pkgs;
  }

  public static resolveLatestPatchVersion(xVersion: string, versions: string[]): string {
    const version = xVersion
      .replace(/\.0(\d)\./, ".$1.") // replace weird docker versions prefixed with 0
      .replace(".x", ".0"); // replace the .x so it can semver parse
    const major = semver.major(version);
    const minor = semver.minor(version);
    let ret = "";
    let retClean = "";
    if (versions) {
      versions.forEach((version: string) => {
        const clean = version.replace(/\.0(\d)\./, ".$1.");
        if (!semver.valid(clean)) {
          return;
        }
        if (semver.major(clean) !== major || semver.minor(clean) !== minor) {
          return;
        }
        if (!ret || semver.gt(clean, retClean)) {
          ret = version;
          retClean = clean;
        }
      });
    }
    if (!ret) {
      throw `latest patch version not found for ${xVersion}`;
    }
    return ret;
  }

  public static latestMinors(versions: string[]): string[] {
    const ret: string[] = _.fill(Array(16), "0.0.0");
    versions.forEach((version: string) => {
      const minor = semver.minor(version);
      const latest = ret[minor];

      if (!latest  || semver.gt(version, latest)) {
        ret[minor] = version;
      }
    });

    return ret;
  }

  public isLatest(): boolean {
    return _.isEqual(this.spec, Installer.latest().spec);
  }

  public flags(): string {
    const flags: string[] = [];
    function getFlags(properties, spec) {
      _.each(properties, (propertySchema, propertyName) => {
        if (!_.has(spec, propertyName)) {
          return;
        }
        if (propertySchema.type === "object") {
          getFlags(propertySchema.properties, spec[propertyName]);
          return;
        }
        const flag = propertySchema.flag;
        if (!flag) {
          return;
        }
        switch (propertySchema.type) {
          case "number": // fallthrough
          case "string":
            flags.push(`${flag}=${spec[propertyName]}`);
            break;
          case "boolean": {
            // This converts advanced options with default true to disable-style bash flags that
            // do not take an arg. i.e. only `velero.installCLI: false` should set the flag
            // velero-disable-cli
            const flagFalseOnlyNoArg = _.get(propertySchema, "flagFalseOnlyNoArg");
            if (flagFalseOnlyNoArg) {
              if (spec[propertyName] === false) {
                flags.push(flag);
              }
            } else {
              flags.push(`${flag}=${spec[propertyName] ? 1 : 0}`);
            }
            break;
          }
        }
      });
    }

    getFlags(specSchema.properties, this.spec);
    return flags.join(" ");
  }

  public hasS3Override(config: string): boolean {
    return _.has(this.spec, [config, "s3Override"]);
  }
}

@Service()
export class InstallerStore {
  private readonly pool: mysql.Pool;

  constructor({ pool }: MysqlWrapper) {
    this.pool = pool;
  }

  @instrumented
  public async getInstaller(installerID: string): Promise<Installer|undefined> {
    if (installerID === "latest") {
      return Installer.latest();
    }

    const q = "SELECT yaml, team_id FROM kurl_installer WHERE kurl_installer_id = ?";
    const v = [installerID];
    const results = await this.pool.query(q, v);

    if (results.length === 0) {
      return;
    }

    const i = Installer.parse(results[0].yaml, results[0].team_id);

    i.id = installerID;
    return i;
  }

  @instrumented
  public async saveAnonymousInstaller(installer: Installer): Promise<void> {
    if (!installer.id) {
      throw new Error("Installer ID is required");
    }
    if (installer.teamID) {
      throw new Error("Anonymous installers must not have team ID");
    }
    if (!Installer.isSHA(installer.id)) {
      throw new Error("Anonymous installers must have generated ID");
    }

    const q = "INSERT IGNORE INTO kurl_installer (kurl_installer_id, yaml) VALUES (?, ?)";
    const v = [installer.id, installer.toYAML()];

    await this.pool.query(q, v);
  }

  @instrumented
  public async saveTeamInstaller(installer: Installer): Promise<void> {
    if (!installer.id) {
      throw new Error("Installer ID is required");
    }
    if (!installer.teamID) {
      throw new Error("Team installers must have team ID");
    }
    if (Installer.isSHA(installer.id)) {
      throw new Error("Team installers must not have generated ID");
    }

    const conn = await this.pool.getConnection();
    await conn.beginTransaction({sql: "", timeout: 10000});

    try {
      const qInsert = "INSERT IGNORE INTO kurl_installer (kurl_installer_id, yaml, team_id) VALUES (?, ?, ?)";
      const vInsert = [installer.id, installer.toYAML(), installer.teamID];

      const resultsInsert = await conn.query(qInsert, vInsert);

      if (resultsInsert.rowsAffected) {
        await conn.commit();
        return;
      }

      // The row already exists. Need to verify team ID.
      const qSelect = "SELECT yaml FROM kurl_installer WHERE kurl_installer_id=? AND team_id=? FOR UPDATE";
      const vSelect = [installer.id, installer.teamID];

      const resultsSelect = await conn.query(qSelect, vSelect);
      if (resultsSelect.length === 0) {
        throw new Forbidden();
      }

      const qUpdate = "UPDATE kurl_installer SET yaml=? WHERE kurl_installer_id=? AND team_id=?";
      const vUpdate = [installer.toYAML(), installer.id, installer.teamID];

      await conn.query(qUpdate, vUpdate);

      await conn.commit();
    } catch (error) {
      await conn.rollback();
      throw error;
    } finally {
      conn.release();
    }
  }
}
