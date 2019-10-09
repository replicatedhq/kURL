import * as crypto from "crypto";
import * as yaml from "js-yaml";
import * as _ from "lodash";
import * as mysql from "promise-mysql";
import { Service } from "ts-express-decorators";
import * as request from "request-promise";
import { MysqlWrapper } from "../util/services/mysql";
import { instrumented } from "monkit";
import { logger } from "../logger";
import { Forbidden } from "../server/errors";

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

export interface RegistryConfig {
  version: string;
}

export interface KotsadmConfig {
  version: string;
  applicationSlug: string;
}

interface ErrorResponse {
  error: any;
}

export class Installer {

  public id: string;
  public kubernetes: KubernetesConfig;
  public weave: WeaveConfig;
  public rook: RookConfig;
  public contour: ContourConfig;
  public registry: RegistryConfig;
  public kotsadm: KotsadmConfig;

  constructor(
    public readonly teamID?: string,
  ) {
    this.kubernetes = { version: "" };
    this.weave = { version: "" };
    this.rook = { version: "" };
    this.contour = { version: "" };
    this.registry = { version: "" };
    this.kotsadm = { version: "", applicationSlug: "" };
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
    if (this.registry && this.registry.version) {
      h.update(`registry_version=${this.registry.version}`);
    }
    if (this.kotsadm && this.kotsadm.version) {
      h.update(`kotsadm_version=${this.kotsadm.version}`);
    }
    if (this.kotsadm && this.kotsadm.applicationSlug) {
      h.update(`kotsadm_applicationSlug=${this.kotsadm.applicationSlug}`);
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
  public registryVersion(): string {
    return _.get(this, "registry.version", "");
  }
  public kotsadmVersion(): string {
    return _.get(this, "kotsadm.version", "");
  }
  public kotsadmApplicationSlug(): string {
    return _.get(this, "kotsadm.applicationSlug", "");
  }

  public dockerVersion(): string {
    return "18.09.8";
  }

  static parse(doc: string, teamID?: string): Installer {
    const parsed = yaml.safeLoad(doc);

    const i = new Installer(teamID);
    i.id = _.get(parsed, "metadata.name", "");
    i.kubernetes = { version: _.get(parsed, "spec.kubernetes.version", "") };
    i.weave = { version: _.get(parsed, "spec.weave.version", "") };
    i.rook = { version: _.get(parsed, "spec.rook.version", "") };
    i.contour = { version: _.get(parsed, "spec.contour.version", "") };
    i.registry = { version: _.get(parsed, "spec.registry.version", "") };
    i.kotsadm = {
      version: _.get(parsed, "spec.kotsadm.version", ""),
      applicationSlug: _.get(parsed, "spec.kotsadm.applicationSlug", ""),
    };

    return i;
  }

  public toYAML(): string {
    // Do not include team ID. May be returned to unauthenticated requests.
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
  registry:
    version: "${this.registryVersion()}"
  kotsadm:
    version: "${this.kotsadmVersion()}"
    applicationSlug: "${this.kotsadmApplicationSlug()}"
`;
  }

  static kubernetesVersions = [
    "1.15.3",
    "1.15.2",
    "1.15.1",
    "1.15.0",
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

  static registryVersions = [
    "2.7.1",
  ];

  // First is "latest" version since kotsadm is not included in default "latest" installer.
  static kotsadmVersions = [
    "0.9.8",
  ];

  static latest(): Installer {
    const i = new Installer();

    i.id = "latest";
    i.kubernetes.version = "1.15.3";
    i.weave.version = "2.5.2";
    i.rook.version = "1.0.4";
    i.contour.version = "0.14.0";
    i.registry.version = "2.7.1";

    return i;
  }

  static latestUnresolved(): Installer {
    const i = new Installer();

    i.id = "latest";
    i.kubernetes.version = "latest";
    i.weave.version = "latest";
    i.rook.version = "latest";
    i.contour.version = "latest";
    i.registry.version = "latest";

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

  static resolveRegistryVersion(version: string): string|null {
    if (version === "latest") {
      return Installer.latest().registryVersion();
    }
    if (_.includes(Installer.registryVersions, version)) {
      return version;
    }
    return null;
  }

  static resolveKotsadmVersion(version: string): string|null {
    if (version === "latest") {
      return Installer.kotsadmVersions[0];
    }
    if (_.includes(Installer.kotsadmVersions, version)) {
      return version;
    }
    return null;
  }

  public resolve(): Installer {
    const i = new Installer();

    i.id = this.id;
    i.kubernetes.version = Installer.resolveKubernetesVersion(this.kubernetesVersion()) || "";
    i.weave.version = Installer.resolveWeaveVersion(this.weaveVersion()) || "";
    i.rook.version = Installer.resolveRookVersion(this.rookVersion()) || "";
    i.contour.version = Installer.resolveContourVersion(this.contourVersion()) || "";
    i.registry.version = Installer.resolveRegistryVersion(this.registryVersion()) || "";
    i.kotsadm.version = Installer.resolveKotsadmVersion(this.kotsadmVersion()) || "";
    i.kotsadm.applicationSlug = this.kotsadmApplicationSlug();

    return i;
  }

  public async validate(): Promise<ErrorResponse|undefined> {
    if (!this.kubernetesVersion()) {
        return { error: { message: "Kubernetes version is required" } };
    }

    const k8sVersion = Installer.resolveKubernetesVersion(this.kubernetesVersion());

    if (!k8sVersion) {
      return { error: { message: `Kubernetes version ${_.escape(this.kubernetesVersion())} is not supported` } };
    }

    if (this.weaveVersion() && !Installer.resolveWeaveVersion(this.weaveVersion())) {
      return { error: { message: `Weave version "${_.escape(this.weaveVersion())}" is not supported` } };
    }

    if (this.rookVersion() && !Installer.resolveRookVersion(this.rookVersion())) {
      return { error: { message: `Rook version "${_.escape(this.rookVersion())}" is not supported` } };
    }

    if (this.contourVersion() && !Installer.resolveContourVersion(this.contourVersion())) {
      return { error: { message: `Contour version "${_.escape(this.contourVersion())}" is not supported` } };
    }

    if (this.registryVersion() && !Installer.resolveRegistryVersion(this.registryVersion())) {
      return { error: { message: `Registry version "${_.escape(this.registryVersion())}" is not supported` } };
    }

    if (this.kotsadmVersion() && !Installer.resolveKotsadmVersion(this.kotsadmVersion())) {
      return { error: { message: `Kotsadm version "${_.escape(this.kotsadmVersion())}" is not supported` } };
    }

    if (this.kotsadmApplicationSlug() && !this.kotsadmVersion()) {
      return { error: { message: `Kotsadm version is required when application slug is set` } };
    }

    if (this.kotsadmApplicationSlug()) {
      // Don't fail validation because replicated.app is unavailable. Only 404 fails validation.
      try {
        await request(`https://replicated.app/metadata/${this.kotsadmApplicationSlug()}`);
      } catch(error) {
        if (error.statusCode === 404) {
          return { error: { message: `Kotsadm application '${_.escape(this.kotsadmApplicationSlug())}' not found` } };
        }
        console.log(`Failed to validate kotsadm application slug: ${error.message}`);
      }
    }
  }

  public packages(): Array<string> {
    const i = this.resolve();

    const pkgs = [
      `common`,
      `kubernetes-${i.kubernetesVersion()}`,
      `docker-${i.dockerVersion()}`,
    ];
    if (i.weaveVersion()) {
      pkgs.push(`weave-${i.weaveVersion()}`);
    }
    if (i.rookVersion()) {
      pkgs.push(`rook-${i.rookVersion()}`);
    }
    if (this.contourVersion()) {
      pkgs.push(`contour-${i.contourVersion()}`);
    }
    if (this.registryVersion()) {
      pkgs.push(`registry-${i.registryVersion()}`);
    }
    if (this.kotsadmVersion()) {
      pkgs.push(`kotsadm-${i.kotsadmVersion()}`);
    }

    return pkgs;
  }

  public isLatest(): boolean {
    return this.kubernetesVersion() === "latest" &&
      this.weaveVersion() === "latest" &&
      this.rookVersion() === "latest" &&
      this.contourVersion() === "latest" &&
      this.registryVersion() === "latest";
  }

  static isSHA(id: string): boolean {
    return /^[0-9a-f]{7}$/.test(id); 
  }

  static isValidSlug(id: string): boolean {
    return /^[0-9a-zA-Z-_]{1,255}$/.test(id);
  }

  static slugIsReserved(id: string): boolean {
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

  public specIsEqual(i: Installer): boolean {
    return this.kubernetesVersion() === i.kubernetesVersion() &&
      this.weaveVersion() === i.weaveVersion() &&
      this.rookVersion() == i.rookVersion() &&
      this.contourVersion() === i.contourVersion() &&
      this.registryVersion() === i.registryVersion();
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
      return Installer.latestUnresolved();
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

  /*
   * @returns boolean - true if new row was inserted. Used to trigger airgap build.
   */
  @instrumented
  public async saveAnonymousInstaller(installer: Installer): Promise<boolean> {
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

    const results = await this.pool.query(q, v);
    return results.affectedRows === 1;
  }

  /*
   * @returns boolean - true if new row was inserted or the yaml spec changes. Used to trigger airgap build.
   */
  @instrumented
  public async saveTeamInstaller(installer: Installer): Promise<boolean> {
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
        return true;
      }

      // The row already exists. Need to verify team ID and determine whether the spec has changed.
      const qSelect = "SELECT yaml FROM kurl_installer WHERE kurl_installer_id=? AND team_id=? FOR UPDATE";
      const vSelect = [installer.id, installer.teamID];

      const resultsSelect = await conn.query(qSelect, vSelect);
      if (resultsSelect.length === 0) {
        throw new Forbidden();
      }

      const old = Installer.parse(resultsSelect[0].yaml, resultsSelect[0].team_id);
      if (old.specIsEqual(installer)) {
        await conn.commit();
        return false;
      }

      const qUpdate = "UPDATE kurl_installer SET yaml=? WHERE kurl_installer_id=? AND team_id=?";
      const vUpdate = [installer.toYAML(), installer.id, installer.teamID];

      await conn.query(qUpdate, vUpdate);

      await conn.commit();
      return true
    } catch(error) {
      await conn.rollback();
      throw error;
    } finally {
      conn.release();
    }
  }
}
