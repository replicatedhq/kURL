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
  private tasksTmpl: () => string;

  constructor() {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";
    this.replicatedAppURL = process.env["REPLICATED_APP_URL"] || "https://replicated.app";
    this.kurlUtilImage = process.env["KURL_UTIL_IMAGE"] || "replicated/kurl-util:alpha";
    this.kurlBinUtils = process.env["KURL_BIN_UTILS_FILE"] || "kurl-bin-utils-latest.tar.gz";

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
    const tasksTmplPath = path.join(tmplDir, "tasks.tmpl");

    const opts = {
      escape: /{{-([\s\S]+?)}}/g,
      evaluate: /{{([\s\S]+?)}}/g,
      interpolate: /{{=([\s\S]+?)}}/g,
    };
    this.installTmpl = _.template(fs.readFileSync(installTmplPath, "utf8"), opts);
    this.joinTmpl = _.template(fs.readFileSync(joinTmplPath, "utf8"), opts);
    this.upgradeTmpl = _.template(fs.readFileSync(upgradeTmplPath, "utf8"), opts);
    this.tasksTmpl = _.template(fs.readFileSync(tasksTmplPath, "utf8"), opts);
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

  public renderTasksScript(): string {
      return this.tasksTmpl();
  }
}

interface Manifest {
  KURL_URL: string;
  DIST_URL: string;
  INSTALLER_ID: string;
  REPLICATED_APP_URL: string;
  KURL_UTIL_IMAGE: string;
  KURL_BIN_UTILS_FILE: string;
  STEP_VERSIONS: string;
  INSTALLER_YAML: string;
}

function manifestFromInstaller(i: Installer, kurlURL: string, replicatedAppURL: string, distURL: string, kurlUtilImage: string, kurlBinUtils: string): Manifest {
  return {
    KURL_URL: kurlURL,
    DIST_URL: distURL,
    INSTALLER_ID: i.id,
    REPLICATED_APP_URL: replicatedAppURL,
    KURL_UTIL_IMAGE: kurlUtilImage,
    KURL_BIN_UTILS_FILE: kurlBinUtils,
    STEP_VERSIONS: `(${Installer.latestMinors().join(" ")})`,
    INSTALLER_YAML: i.toYAML(),
  };
}
