import * as fs from "fs";
import * as path from "path";
import * as _ from "lodash";
import {Service} from "ts-express-decorators";
import { Installer } from "../../installers";

@Service()
export class Templates {

  private kurlURL: string;
  private distURL: string;
  private replicatedAppURL: string;
  private kurlUtilImage: string;
  private kurlBinUtils: string;
  private installTmpl: (obj: any) => string;
  private joinTmpl: (obj: any) => string;
  private upgradeTmpl: (obj: any) => string;

  constructor() {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";
    this.replicatedAppURL = process.env["REPLICATED_APP_URL"] || "https://replicated.app";
    this.kurlUtilImage = process.env["KURL_UTIL_IMAGE"] || "replicated/kurl-util:alpha";
    this.kurlBinUtils = process.env["KURL_BIN_UTILS_FILE"] || "staging/kurl-bin-utils-latest.tar.gz";

    this.distURL = `https://${process.env["KURL_BUCKET"]}.s3.amazonaws.com`;
    if (process.env["NODE_ENV"] === "production") {
      this.distURL += "/dist";
    } else {
      this.distURL += "/staging";
    }

    const tmplDir = path.join(__dirname, "../../../../templates");
    const installTmplPath = path.join(tmplDir, "install.tmpl");
    const joinTmplPath = path.join(tmplDir, "join.tmpl");
    const upgradeTmplPath = path.join(tmplDir, "upgrade.tmpl");

    const opts = {
      escape: /{{-([\s\S]+?)}}/g,
      evaluate: /{{([\s\S]+?)}}/g,
      interpolate: /{{=([\s\S]+?)}}/g,
    };
    this.installTmpl = _.template(fs.readFileSync(installTmplPath, "utf8"), opts);
    this.joinTmpl = _.template(fs.readFileSync(joinTmplPath, "utf8"), opts);
    this.upgradeTmpl = _.template(fs.readFileSync(upgradeTmplPath, "utf8"), opts);
  }

  public renderInstallScript(i: Installer): string {
    return this.installTmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL, this.distURL, this.kurlUtilImage, this.kurlBinUtils));
  }

  public renderJoinScript(i: Installer): string {
    return this.joinTmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL, this.distURL, this.kurlUtilImage, this.kurlBinUtils));
  }

  public renderUpgradeScript(i: Installer): string {
    return this.upgradeTmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL, this.distURL, this.kurlUtilImage, this.kurlBinUtils));
  }
}

interface Manifest {
  KURL_URL: string;
  DIST_URL: string;
  INSTALLER_ID: string;
  KUBERNETES_VERSION: string;
  WEAVE_VERSION: string;
  ROOK_VERSION: string;
  OPENEBS_VERSION: string;
  MINIO_VERSION: string;
  CONTOUR_VERSION: string;
  REGISTRY_VERSION: string;
  PROMETHEUS_VERSION: string;
  FLUENTD_VERSION: string;
  KOTSADM_VERSION: string;
  KOTSADM_APPLICATION_SLUG: string;
  REPLICATED_APP_URL: string;
  VELERO_VERSION: string;
  EKCO_VERSION: string;
  FLAGS: string;
  KURL_UTIL_IMAGE: string;
  KURL_BIN_UTILS_FILE: string;
  DOCKER_VERSION: string;
  INSTALLER_YAML: string;
}

function manifestFromInstaller(i: Installer, kurlURL: string, replicatedAppURL: string, distURL: string, kurlUtilImage: string, kurlBinUtils: string): Manifest {
  return {
    KURL_URL: kurlURL,
    DIST_URL: distURL,
    INSTALLER_ID: i.id,
    KUBERNETES_VERSION: i.spec.kubernetes.version,
    WEAVE_VERSION: _.get(i.spec, "weave.version", ""),
    ROOK_VERSION: _.get(i.spec, "rook.version", ""),
    OPENEBS_VERSION: _.get(i.spec, "openebs.version", ""),
    MINIO_VERSION: _.get(i.spec, "minio.version", ""),
    CONTOUR_VERSION: _.get(i.spec, "contour.version", ""),
    REGISTRY_VERSION: _.get(i.spec, "registry.version", ""),
    PROMETHEUS_VERSION: _.get(i.spec, "prometheus.version", ""),
    FLUENTD_VERSION: _.get(i.spec, "fluentd.version", ""),
    KOTSADM_VERSION: _.get(i.spec, "kotsadm.version", ""),
    KOTSADM_APPLICATION_SLUG: _.get(i.spec, "kotsadm.applicationSlug", ""),
    REPLICATED_APP_URL: replicatedAppURL,
    VELERO_VERSION: _.get(i.spec, "velero.version", ""),
    EKCO_VERSION: _.get(i.spec, "ekco.version", ""),
    DOCKER_VERSION: _.get(i.spec, "docker.version", ""),
    FLAGS: i.flags(),
    KURL_UTIL_IMAGE: kurlUtilImage,
    KURL_BIN_UTILS_FILE: kurlBinUtils,
    INSTALLER_YAML: i.toYAML(),
  };
}
