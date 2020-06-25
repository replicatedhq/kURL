import * as crypto from "crypto";
import * as yaml from "js-yaml";
import * as _ from "lodash";
import * as mysql from "promise-mysql";
import { Service } from "ts-express-decorators";
import * as request from "request-promise";
import * as AJV from "ajv";
import { MysqlWrapper } from "../util/services/mysql";
import { instrumented } from "monkit";
import { logger } from "../logger";
import { Forbidden } from "../server/errors";

interface ErrorResponse {
  error: any;
}

export interface KubernetesConfig {
  version: string;
  serviceCidrRange?: string;
  serviceCIDR?: string;
  HACluster?: boolean;
  masterAddress?: string;
  loadBalancerAddress?: string;
  bootstrapToken?: string;
  bootstrapTokenTTL?: string;
  kubeadmTokenCAHash?: string;
  controlPlane?: boolean;
  certKey?: string;
}

export const kubernetesConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    serviceCidrRange: { type: "string", flag: "service-cidr-range", description: "The size of the CIDR for Kubernetes (can be presented as just a number or with a preceding slash)" },
    serviceCIDR: { type: "string", flag: "service-cidr", description: "This defines subnet for kubernetes" },
    HACluster: { type: "boolean", flag: "ha", description: "Create the cluster as a high availability cluster (note that this needs a valid load balancer address and additional nodes to be a truly HA cluster)" },
    masterAddress: { type: "string", flag: "kuberenetes-master-address", description: "The address of the internal Kubernetes API server, used during join scripts (read-only)" },
    loadBalancerAddress: { type: "string", flag: "load-balancer-address", description: "Used for High Availability installs, indicates the address of the external load balancer" },
    bootstrapToken: { type: "string", flag: "bootstrap-token", description: "A secret needed for new nodes to join an existing cluster" },
    bootstrapTokenTTL: { type: "string", flag: "bootstrap-token-ttl", description: "How long the bootstrap token is valid for" },
    kubeadmTokenCAHash: { type: "string", flag: "kubeadm-token-ca-hash", description: "Generated during the install script, used for nodes joining (read-only)" },
    controlPlane: { type: "boolean", flag: "control-plane", description: "Used during a join script to indicate that the node will be an additional master (read-only)" },
    certKey: { type: "string", flag: "cert-key", description: "A secret needed for new master nodes to join an existing cluster (read-only)" },
  },
  required: [ "version" ],
  additionalProperties: false,
};

export interface DockerConfig {
  version: string;
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
    bypassStorageDriverWarnings: { type: "boolean" , flag: "bypass-storagedriver-warnings", description: "Force docker to ignore if using devicemapper storage driver in loopback mode" },
    hardFailOnLoopback: { type: "boolean", flag: "hard-fail-on-loopback", description: "The install script stops and exits if it detects a loopback file storage configuration" },
    noCEOnEE: { type: "boolean", flag: "no-ce-on-ee", description: "Do not install Docker-CE on RHEL" },
    dockerRegistryIP: { type: "string", flag: "docker-registry-ip", description: "Used during join scripts, indicates the address of the docker registry (read only)" },
    additionalNoProxy: { type: "string", flag: "additional-no-proxy", description: "This indicates addresses that should not be proxied in addition to the private IP (This can be a comma separated list of IPs or just 1 IP)" },
    noDocker: { type: "boolean", flag: "no-docker", description: "Do not install Docker" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface WeaveConfig {
  version: string;
  podCIDR?: string;
  podCidrRange?: string;
  IPAllocRange?: string; // deprecated, will be converted to podCidrRange
  encryptNetwork?: boolean; // deprectaed, will be converted to isEncryptionDisabled
  isEncryptionDisabled?: boolean;
}

export const weaveConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    podCIDR: { type: "string", flag: "pod-cidr", description: "The subnet where pods will be found" },
    podCidrRange: { type: "string", flag: "pod-cidr-range", description: "The size of the CIDR where pods can be found" },
    isEncryptionDisabled: { type: "boolean", flag: "disable-weave-encryption", description: "Is encryption in the Weave CNI disabled" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface RookConfig {
  version: string;
  storageClass?: string; // deprecated, will be converted to storageClassName
  cephPoolReplicas?: number; // deprecated, will be converted to cephReplicaCount
  cephReplicaCount?: number;
  storageClassName?: string;
  isBlockStorageEnabled?: boolean;
  blockDeviceFilter?: string;
}

export const rookConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    storageClassName: { type: "string", flag: "storage-class-name", description: "The name of the StorageClass used by rook" },
    cephReplicaCount: { type: "number", flag: "ceph-replica-count", description: "The number of replicas in the Rook Ceph pool" },
    isBlockStorageEnabled: { type: "boolean", flag: "rook-block-storage-enabled", description: "Use block devices instead of the filesystem for storage in the Ceph cluster" },
    blockDeviceFilter: { type: "string", flag: "rook-block-device-filter", description: "Only use block devices matching this regex" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface OpenEBSConfig {
  version: string;
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
  namespace?: string;
}

export const minioConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    namespace: { type: "string", flag: "minio-namespace", description: "The namespace Minio is installed to" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface ContourConfig {
  version: string;
  tlsMinimumProtocolVersion?: string;
}

export const contourConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    tlsMinimumProtocolVersion: { type: "string", flag: "contour-tls-minimum-protocol-version", description: "The minimum TLS protocol version that is allowed (default 1.2)." },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface RegistryConfig {
  version: string;
  publishPort?: number;
}

export const registryConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    publishPort: { type: "number", flag: "registry-publish-port", description: "add a NodePort service to the registry" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface PrometheusConfig {
  version: string;
}

export const prometheusConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface FluentdConfig {
  version: string;
  fullEFKStack?: boolean;
  efkStack?: boolean;
}

export const fluentdConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    fullEFKStack : { type: "boolean", flag: "fluentd-full-efk-stack", description: "Install ElasticSearch and Kibana in addition to Fluentd" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface KotsadmConfig {
  version: string;
  applicationSlug?: string;
  uiBindPort?: number;
  hostname?: string;
  applicationNamespace?: string;
}

export const kotsadmConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
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
  namespace?: string;
  disableCLI?: boolean;
  disableRestic?: boolean;
  localBucket?: string;
}

export const veleroConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    namespace: { type: "string", flag: "velero-namespace", description: "The namespace to install velero into if not using the default"},
    localBucket: { type: "string", flag : "velero-local-bucket", description: "Name of the bucket to create snapshots in the local object store"},
    disableCLI: { type: "boolean", flag: "velero-disable-cli", description: "Don't install the velero CLI on the host" },
    disableRestic: { type: "boolean", flag: "velero-disable-restic", description: "Don’t install the restic integration" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface EkcoConfig {
  version: string;
  nodeUnreachableToleration?: string;
  minReadyMasterNodeCount?: number;
  minReadyWorkerNodeCount?: number;
  shouldDisableRebootService?: boolean;
  rookShouldUseAllNodes?: boolean;
}

export const ekcoConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    nodeUnreachableToleration: { type: "string", flag: "ekco-node-unreachable-toleration-duration" , description: "How long a Node must have status unreachable before it’s purged" },
    minReadyMasterNodeCount: { type: "number", flag: "ekco-min-ready-master-node-count" , description: "Ekco will not purge a master node if it would result in less than this many masters remaining" },
    minReadyWorkerNodeCount: { type: "number", flag: "ekco-min-ready-worker-node-count" , description: "Ekco will not purge a worker node if it would result in less than this many workers remaining" },
    shouldDisableRebootService: { type: "boolean", flag: "ekco-should-disable-reboot-service" , description: "Do not install the systemd shutdown service that cordons a node and deletes pods with PVC and Shared FS volumes mounted" },
    rookShouldUseAllNodes: { type: "boolean", flag: "ekco-rook-should-use-all-nodes" , description: "This will disable management of nodes in the CephCluster resource. If false, ekco will add nodes to the storage list and remove them when a node is purged" },
  },
  required: ["version"],
  // additionalProperties: false,
};

export interface KurlConfig {
  proxyAddress?: string;
  additionalNoProxyAddresses: string[];
  airgap?: boolean;
  bypassFirewalldWarning?: boolean;
  hardFailOnFirewalld?: boolean;
  hostnameCheck?: string;
  noProxy?: string;
  privateAddress?: string;
  publicAddress?: string;
  task?: string;
}

export const kurlConfigSchema = {
  type: "object",
  properties: {
    proxyAddress: { type: "string", flag: "http-proxy" , description: "The address of the proxy to use for outbound connections" },
    additionalNoProxyAddresses: { type: "array", items: { type: "string" }, description: "Addresses that can be reached without a proxy" },
    airgap: { type: "boolean", flag: "airgap", description: "Indicates if this install is an airgap install" },
    bypassFirewalldWarning: { type: "boolean", flag: "bypass-firewalld-warning" , description: "Continue installing even if the firewalld service is active" },
    hardFailOnFirewalld: { type: "boolean", flag: "hard-fail-on-firewalld" , description: "Exit the install script if the firewalld service is active" },
    hostnameCheck: { type: "string", flag: "hostname-check" , description: "Used as a check during an upgrade to ensure the script will run only on the given hostname" },
    noProxy: { type: "boolean", flag: "no-proxy" , description: "Don’t detect or configure a proxy" },
    privateAddress: { type: "string", flag: "private-address" , description: "The local address of the host (different for each host in the cluster)" },
    publicAddress: { type: "string", flag: "public-address" , description: "The public address of the host (different for each host in the cluster), will be added as a CNAME to the k8s API server cert so you can use kubectl with this address" },
  },
  additionalProperties: false,
};

export interface ContainerdConfig {
  version: string;
}

export const containerdConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface InstallerSpec {
  kubernetes: KubernetesConfig;
  docker?: DockerConfig;
  weave?: WeaveConfig;
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
}

const specSchema = {
  type: "object",
  properties: {
    // order here determines order in rendered yaml
    kubernetes: kubernetesConfigSchema,
    docker: dockerConfigSchema,
    weave: weaveConfigSchema,
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
  },
  required: ["kubernetes"],
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
  // first version of each is "latest"
  public static versions = {
    kubernetes: [
      "1.17.3",
      "1.16.4",
      "1.15.3",
      "1.15.2",
      "1.15.1",
      "1.15.0",
    ],
    docker: [
      "19.03.4",
      "18.09.8",
    ],
    containerd: [
      "1.2.13",
    ],
    weave: [
      "2.6.4",
      "2.5.2",
    ],
    rook: [
      "1.0.4",
    ],
    contour: [
      "1.0.1",
      "0.14.0",
    ],
    registry: [
      "2.7.1",
    ],
    prometheus: [
      "0.33.0",
    ],
    fluentd: [
      "1.7.4",
    ],
    kotsadm: [
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
      "alpha",
    ],
    velero: [
      "1.2.0",
    ],
    openebs: [
      "1.6.0",
    ],
    minio: [
      "2020-01-25T02-50-51Z",
    ],
    ekco: [
      "0.2.4",
      "0.2.3",
      "0.2.1",
      "0.2.0",
      "0.1.0",
    ],
  };

  public static latest(): Installer {
    const i = new Installer();

    i.id = "latest";
    i.spec.kubernetes = { version: "latest" };
    i.spec.docker = { version: "latest" };
    i.spec.weave = { version: "latest" };
    i.spec.rook = { version: "latest" };
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
    const parsed = yaml.safeLoad(doc);

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
        if (i.spec.weave.encryptNetwork !== undefined){
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

  public static hasVersion(config: string, version: string): boolean {
    if (version === "latest") {
      return true;
    }
    if (_.includes(Installer.versions[config], version)) {
      return true;
    }
    return false;
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
    return yaml.safeDump(this.toObject());
  }

  public toObject(): InstallerObject {
    const obj = {
      apiVersion: "cluster.kurl.sh/v1beta1",
      kind: "Installer",
      metadata: {
        name: `${this.id}`,
      },
      spec: { kubernetes: _.cloneDeep(this.spec.kubernetes) },
    };

    // add spec properties in order they should be rendered in yaml
    _.each(specSchema.properties, (val, key) => {
      if (this.spec[key]) {
        obj.spec[key] = _.cloneDeep(this.spec[key]);
      }
    });

    return obj;
  }

  public resolve(): Installer {
    const i = this.clone();

    _.each(_.keys(i.spec), (config) => {
      if (i.spec[config].version === "latest") {
        i.spec[config].version = _.first(Installer.versions[config]);
      }
    });

    return i;
  }

  public validate(): ErrorResponse|undefined {
    if (!this.spec || !this.spec.kubernetes || !this.spec.kubernetes.version) {
        return { error: { message: "Kubernetes version is required" } };
    }

    const ajv = new AJV();
    const validate = ajv.compile(specSchema);
    const valid = validate(this.spec);

    if (!valid && validate.errors && validate.errors.length) {
      const err = validate.errors[0];
      const message = `spec${err.dataPath} ${err.message}`;
      return { error: { message } };
    }

    if (!Installer.hasVersion("kubernetes", this.spec.kubernetes.version)) {
      return { error: { message: `Kubernetes version ${_.escape(this.spec.kubernetes.version)} is not supported` } };
    }
    if (this.spec.kubernetes.serviceCidrRange && !Installer.isValidCidrRange(this.spec.kubernetes.serviceCidrRange)) {
      return { error: { message: `Kubernetes serviceCidrRange "${_.escape(this.spec.kubernetes.serviceCidrRange)}" is invalid` } };
    }
    if (this.spec.weave && !Installer.hasVersion("weave", this.spec.weave.version)) {
      return { error: { message: `Weave version "${_.escape(this.spec.weave.version)}" is not supported` } };
    }
    if (this.spec.weave && this.spec.weave.podCidrRange && !Installer.isValidCidrRange(this.spec.weave.podCidrRange)) {
      return { error: { message: `Weave podCidrRange "${_.escape(this.spec.weave.podCidrRange)}" is invalid` } };
    }
    if (this.spec.rook && !Installer.hasVersion("rook", this.spec.rook.version)) {
      return { error: { message: `Rook version "${_.escape(this.spec.rook.version)}" is not supported` } };
    }
    if (this.spec.contour && !Installer.hasVersion("contour", this.spec.contour.version)) {
      return { error: { message: `Contour version "${_.escape(this.spec.contour.version)}" is not supported` } };
    }
    if (this.spec.registry && !Installer.hasVersion("registry", this.spec.registry.version)) {
      return { error: { message: `Registry version "${_.escape(this.spec.registry.version)}" is not supported` } };
    }
    if (this.spec.prometheus && !Installer.hasVersion("prometheus", this.spec.prometheus.version)) {
      return { error: { message: `Prometheus version "${_.escape(this.spec.prometheus.version)}" is not supported` } };
    }
    if (this.spec.fluentd && !Installer.hasVersion("fluentd", this.spec.fluentd.version)) {
      return { error: { message: `Fluentd version "${_.escape(this.spec.fluentd.version)}" is not supported` } };
    }
    if (this.spec.kotsadm) {
      if (!Installer.hasVersion("kotsadm", this.spec.kotsadm.version)) {
        return { error: { message: `Kotsadm version "${_.escape(this.spec.kotsadm.version)}" is not supported` } };
      }
    }
    if (this.spec.velero && !Installer.hasVersion("velero", this.spec.velero.version)) {
      return { error: { message: `Velero version "${_.escape(this.spec.velero.version)}" is not supported` } };
    }
    if (this.spec.openebs && !Installer.hasVersion("openebs", this.spec.openebs.version)) {
      return { error: { message: `OpenEBS version "${_.escape(this.spec.openebs.version)}" is not supported` } };
    }
    if (this.spec.minio && !Installer.hasVersion("minio", this.spec.minio.version)) {
      return { error: { message: `Minio version "${_.escape(this.spec.minio.version)}" is not supported` } };
    }
    if (this.spec.ekco && !Installer.hasVersion("ekco", this.spec.ekco.version)) {
      return { error: { message: `Ekco version "${_.escape(this.spec.ekco.version)}" is not supported` } };
    }
    if (this.spec.containerd && !Installer.hasVersion("containerd", this.spec.containerd.version)) {
      return { error: { message: `Containerd version "${_.escape(this.spec.containerd.version)}" is not supported` } };
    }
    if (this.spec.containerd && this.spec.docker) {
      return { error: { message: `This spec contains both docker and containerd, please specifiy only one CRI` } };
    }
  }

  public packages(): string[] {
    const i = this.resolve();

    const binUtils = String(process.env["KURL_BIN_UTILS_FILE"]).slice(0, -7); // remove .tar.gz
    const pkgs = [ "common", binUtils ];

    _.each(_.keys(this.spec), (config: string) => {
      const version = this.spec[config].version;
      if (version) {
        pkgs.push(`${config}-${this.spec[config].version}`);
      }
    });

    return pkgs;
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
        case "boolean":
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
      });
    }

    getFlags(specSchema.properties, this.spec);
    return flags.join(" ");
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
