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
  KOTSADM_VERSION: string;
  KOTSADM_APPLICATION_SLUG: string;
  REPLICATED_APP_URL: string;
}

function manifestFromInstaller(i: Installer, kurlURL: string, replicatedAppURL: string): Manifest {
  return {
    KURL_URL: kurlURL,
    INSTALLER_ID: i.id,
    KUBERNETES_VERSION: i.kubernetesVersion(),
    WEAVE_VERSION: i.weaveVersion(),
    ROOK_VERSION: i.rookVersion(),
    CONTOUR_VERSION: i.contourVersion(),
    REGISTRY_VERSION: i.registryVersion(),
    KOTSADM_VERSION: i.kotsadmVersion(),
    KOTSADM_APPLICATION_SLUG: i.kotsadmApplicationSlug(),
    REPLICATED_APP_URL: replicatedAppURL,
  };
}

