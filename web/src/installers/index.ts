import * as crypto from "crypto";
import * as yaml from "js-yaml";
import * as _ from "lodash";
import * as mysql from "promise-mysql";
import { Service } from "ts-express-decorators";
import { MysqlWrapper } from "../util/services/mysql";
import { instrumented } from "monkit";
import { logger } from "../logger";

export interface KubernetesConfig {
  version: string;
}

export interface WeaveConfig {
  version: string;
}

export interface RookConfig {
  version: string;
}

export interface ContourConfig {
  version: string;
}

export class Installer {

  public id: string;
  public kubernetes: KubernetesConfig;
  public weave: WeaveConfig;
  public rook: RookConfig;
  public contour: ContourConfig;

  constructor() {
    this.kubernetes = { version: "" };
    this.weave = { version: "" };
    this.rook = { version: "" };
    this.contour = { version: "" };
  }

  public hash(): string {
    const h = crypto.createHash('sha256');

    if (this.kubernetes && this.kubernetes.version) {
      h.update(`kubernetes_version=${this.kubernetes.version}`);
    }
    if (this.weave && this.weave.version) {
      h.update(`weave_version=${this.weave.version}`);
    }
    if (this.rook && this.rook.version) {
      h.update(`rook_version=${this.rook.version}`);
    }
    if (this.contour && this.contour.version) {
      h.update(`contour_version=${this.contour.version}`);
    }

    return h.digest('hex').substring(0,7);
  }

  // I don't trust the type system
  public kubernetesVersion(): string {
    return _.get(this, "kubernetes.version", "");
  }
  public weaveVersion(): string {
    return _.get(this, "weave.version", "");
  }
  public rookVersion(): string {
    return _.get(this, "rook.version", "");
  }
  public contourVersion(): string {
    return _.get(this, "contour.version", "");
  }

  static parse(doc: string): Installer {
    const parsed = yaml.safeLoad(doc);

    const i = new Installer()
    i.id = _.get(parsed, "metadata.name", "");
    i.kubernetes = { version: _.get(parsed, "spec.kubernetes.version", "") };
    i.weave = { version: _.get(parsed, "spec.weave.version", "") };
    i.rook = { version: _.get(parsed, "spec.rook.version", "") };
    i.contour = { version: _.get(parsed, "spec.contour.version", "") };

    return i;
  }

  public toYAML(): string {
    return `apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "${this.id}"
spec:
  kubernetes:
    version: "${this.kubernetesVersion()}"
  weave:
    version: "${this.weaveVersion()}"
  rook:
    version: "${this.rookVersion()}"
  contour:
    version: "${this.contourVersion()}"
`;
  }

  static kubernetesVersions = [
    "1.15.1",
  ];

  static weaveVersions = [
    "2.5.2",
  ];

  static rookVersions = [
    "1.0.4",
  ];

  static contourVersions = [
    "0.14.0",
  ];

  static latest(): Installer {
    const i = new Installer();

    i.id = "latest";
    i.kubernetes.version = "1.15.1";
    i.weave.version = "2.5.2";
    i.rook.version = "1.0.4";
    i.contour.version = "0.14.0";

    return i;
  }

  static resolveKubernetesVersion(version: string): string|null {
    if (version === "latest") {
      return Installer.latest().kubernetesVersion();
    }
    if (_.includes(Installer.kubernetesVersions, version)) {
      return version;
    }
    return null;
  }

  static resolveWeaveVersion(version: string): string|null {
    if (version === "latest") {
      return Installer.latest().weaveVersion();
    }
    if (_.includes(Installer.weaveVersions, version)) {
      return version;
    }
    return null;
  }

  static resolveRookVersion(version: string): string|null {
    if (version === "latest") {
      return Installer.latest().rookVersion();
    }
    if (_.includes(Installer.rookVersions, version)) {
      return version;
    }
    return null;
  }

  static resolveContourVersion(version: string): string|null {
    if (version === "latest") {
      return Installer.latest().contourVersion();
    }
    if (_.includes(Installer.contourVersions, version)) {
      return version;
    }
    return null;
  }

  public validate(): Error|undefined {
    const k8sVersion = Installer.resolveKubernetesVersion(this.kubernetesVersion());

    if (!k8sVersion) {
      // TODO static errors
      return new Error("Kubernetes version is required");
    }

    if (this.weaveVersion() && !Installer.resolveWeaveVersion(this.weaveVersion())) {
      return new Error("Weave version is invalid");
    }

    if (this.rookVersion() && !Installer.resolveRookVersion(this.rookVersion())) {
      return new Error("Rook version is invalid");
    }

    if (this.contourVersion() && !Installer.resolveContourVersion(this.contourVersion())) {
      return new Error("Contour version is invalid");
    }
  }

  public isLatest(): boolean {
    return this.kubernetesVersion() === "latest" &&
      this.weaveVersion() === "latest" &&
      this.rookVersion() === "latest" &&
      this.contourVersion() === "latest";
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

    try {
      const q = "SELECT yaml FROM kurl_installers WHERE kurl_installer_id = ?"
      const v = [installerID];
      const results = await this.pool.query(q, v);

      if (results.length === 0) {
        return;
      }

      const i = Installer.parse(results[0].yaml);
      i.id = installerID;
      return i;
    } catch (error) {
      logger.error(error);
      return;
    }
  }

  @instrumented
  public async saveInstaller(installer: Installer): Promise<undefined> {
    try {
      const q = "INSERT INTO kurl_installers (kurl_installer_id, yaml) VALUES (?, ?) ON DUPLICATE KEY UPDATE yaml=VALUES(yaml)";
      const v = [installer.id, installer.toYAML()];

      const results = await this.pool.query(q, v);
    } catch (error) {
      logger.error(error);
      return;
    }
  }
}
