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
  haCluster?: boolean;
  masterAddress?: string;
  loadBalancerAddress?: string;
  bootstrapToken?: string;
  bootstrapTokenTTL?: string;
  kubeadmTokenCAHash?: string;
  controlPlane?: boolean;
  certKey?: string;
  apiServiceAddress?: string;
}

const kubernetesConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    serviceCidrRange: { type: "string", flag: "service-cidr-range" },
    serviceCIDR: { type: "string", flag: "service-cidr" },
    haCluster: { type: "boolean", flag: "ha" },
    masterAddress: { type: "string", flag: "kuberenetes-master-address" },
    loadBalancerAddress: { type: "string", flag: "load-balancer-address" },
    bootstrapToken: { type: "string", flag: "bootstrap-token" },
    bootstrapTokenTTL: { type: "string", flag: "bootstrap-token-ttl" },
    kubeadmTokenCAHash: { type: "string", flag: "kubeadm-token-ca-hash" },
    controlPlane: { type: "boolean", flag: "control-plane"},
    certKey: { type: "string", flag: "cert-key" },
    apiServiceAddress: { type: "string", flag: "api-service-address" },
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

const dockerConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    bypassStorageDriverWarnings: { type: "boolean" , flag: "bypass-storagedriver-warnings" },
    hardFailOnLoopback: { type: "boolean", flag: "hard-fail-on-loopback" },
    noCEOnEE: { type: "boolean", flag: "no-ce-on-ee" },
    dockerRegistryIP: { type: "string", flag: "docker-registry-ip" },
    additionalNoProxy: { type: "string", flag: "additional-no-proxy" },
    noDocker: { type: "boolean", flag: "no-docker" },
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

const weaveConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    podCIDR: { type: "string", flag: "pod-cidr" },
    podCidrRange: { type: "string", flag: "pod-cidr-range" },
    isEncryptionDisabled: { type: "boolean", flag: "disable-weave-encryption" },
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
}

const rookConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    storageClassName: { type: "string", flag: "storage-class-name" },
    cephReplicaCount: { type: "number", flag: "ceph-replica-count" },
  },
  required: [ "version" ],
  additionalProperites: false,
};

export interface OpenEBSConfig {
  version: string;
  namespace?: string;
  localPV?: boolean;
  localPVStorageClass?: string;
}

const openEBSConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    namespace: { type: "string", flag: "openebs-namespace" },
    localPV: { type: "boolean", flag: "openebs-localpv" },
    localPVStorageClass: { type: "string", flag: "openebs-localpv-storage-class" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface MinioConfig {
  version: string;
  namespace?: string;
}

const minioConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    namespace: { type: "string", flag: "minio-namespace" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface ContourConfig {
  version: string;
}

const contourConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface RegistryConfig {
  version: string;
  publishPort?: number;
}

const registryConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    publishPort: { type: "number", flag: "registry-publish-port" },
  },
  required: ["version"],
  additionalProperties: false,
};

export interface PrometheusConfig {
  version: string;
}

const prometheusConfigSchema = {
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
}

const fluentdConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    fullEFKStack : { type: "boolean", flag: "fluentd-full-efk-stack" },
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

const kotsadmConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    applicationSlug: { type: "string", flag: "kotsadm-application-slug" },
    uiBindPort: { type: "number", flag: "kotsadm-ui-bind-port" },
    hostname: { type: "string", flag: "kotsadm-hostname" },
    applicationNamespace: { type: "string", flag: "kotsadm-application-namespaces" },
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

const veleroConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    namespace: { type: "string", flag: "velero-namespace" },
    localBucket: { type: "string", flag : "velero-local-bucket"},
    disableCLI: { type: "boolean", flag: "velero-disable-cli" },
    disableRestic: { type: "boolean", flag: "velero-disable-restic"},
  },
  required: ["version"],
  additionalProperties: false,
};

export interface EkcoConfig {
  version: string;
  nodeUnreachableTolerationDuration?: string;
  minReadyMasterNodeCount?: number;
  minReadyWorkerNodeCount?: number;
  shouldDisableRebootService?: boolean;
  rookShouldUseAllNodes?: boolean;
}

const ekcoConfigSchema = {
  type: "object",
  properties: {
    version: { type: "string" },
    nodeUnreachableTolerationDuration: { type: "string", flag: "ekco-node-unreachable-toleration-duration" },
    minReadyMasterNodeCount: { type: "number", flag: "ekco-min-ready-master-node-count" },
    minReadyWorkerNodeCount: { type: "number", flag: "ekco-min-ready-worker-node-count" },
    shouldDisableRebootService: { type: "boolean", flag: "ekco-should-disable-reboot-service" },
    rookShouldUseAllNodes: { type: "boolean", flag: "ekco-rook-should-use-all-nodes" },
  },
  required: ["version"],
  additionalProperties: false,
}

export interface KurlConfig {
  HTTPProxy?: string;
  airgap?: boolean;
  bypassFirewalldWarning?: boolean;
  hardFailOnFirewalld?: boolean;
  hostnameCheck?: string;
  noProxy?: string;
  privateAddress?: string;
  publicAddress?: string;
  task?: string;
}

const kurlConfigSchema = {
  type: "object",
  properties: {
    HTTPProxy: { type: "string", flag: "http-proxy" },
    airgap: { type: "boolean", flag: "airgap" },
    bypassFirewalldWarning: { type: "boolean", flag: "bypass-firewalld-warning" },
    hardFailOnFirewalld: { type: "boolean", flag: "hard-fail-on-firewalld" },
    hostnameCheck: { type: "string", flag: "hostname-check" },
    noProxy: { type: "boolean", flag: "no-proxy" },
    privateAddress: { type: "string", flag: "private-address" },
    publicAddress: { type: "string", flag: "public-address" },
    task: { type: "string", flag: "task" },
  },
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
      "1.16.4",
      "1.15.3",
      "1.15.2",
      "1.15.1",
      "1.15.0",
    ],
    docker: [
      "18.09.8",
    ],
    weave: [
      "2.5.2",
    ],
    rook: [
      "1.0.4",
    ],
    contour: [
      "0.14.0",
      // Before making 1.0.1 latest need
      // to test if upgrading from previous version works.
      "1.0.1",
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
      "0.2.2",
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
    const i = parseInt(range.replace(/^\//, ""));
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
  }

  public packages(): string[] {
    const i = this.resolve();

    const pkgs = [ "common" ];

    _.each(_.keys(this.spec), (config: string) => {
      pkgs.push(`${config}-${this.spec[config].version}`);
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
