import * as fs from "fs";
import * as path from "path";
import * as _ from "lodash";
import {Service} from "ts-express-decorators";
import { Installer } from "../../installers";


@Service()
export class Templates {

  private kurlURL: string;
  private replicatedAppURL: string;
  private installTmpl: (any) => string;
  private joinTmpl: (any) => string;
  private upgradeTmpl: (any) => string;

  constructor () {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";
    this.replicatedAppURL = process.env["REPLICATED_APP_URL"] || "https://replicated.app";

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
    return this.installTmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL));
  }

  public renderJoinScript(i: Installer): string {
    return this.joinTmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL));
  }

  public renderUpgradeScript(i: Installer): string {
    return this.upgradeTmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL));
  }
}

interface Manifest {
  KURL_URL: string;
  INSTALLER_ID: string;
  KUBERNETES_VERSION: string;
  WEAVE_VERSION: string;
  ROOK_VERSION: string;
  CONTOUR_VERSION: string;
  REGISTRY_VERSION: string;
  PROMETHEUS_VERSION: string;
  KOTSADM_VERSION: string;
  KOTSADM_APPLICATION_SLUG: string;
  REPLICATED_APP_URL: string;
  FLAGS: string;
}

function manifestFromInstaller(i: Installer, kurlURL: string, replicatedAppURL: string): Manifest {
  return {
    KURL_URL: kurlURL,
    INSTALLER_ID: i.id,
    KUBERNETES_VERSION: i.spec.kubernetes.version,
    WEAVE_VERSION: _.get(i.spec, "weave.version", ""),
    ROOK_VERSION: _.get(i.spec, "rook.version", ""),
    CONTOUR_VERSION: _.get(i.spec, "contour.version", ""),
    REGISTRY_VERSION: _.get(i.spec, "registry.version", ""),
    PROMETHEUS_VERSION: _.get(i.spec, "prometheus.version", ""),
    KOTSADM_VERSION: _.get(i.spec, "kotsadm.version", ""),
    KOTSADM_APPLICATION_SLUG: _.get(i.spec, "kotsadm.applicationSlug", ""),
    REPLICATED_APP_URL: replicatedAppURL,
    FLAGS: i.flags(),
  };
}

