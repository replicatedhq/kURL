import * as fs from "fs";
import * as path from "path";
import * as _ from "lodash";
import {Service} from "ts-express-decorators";
import { Installer } from "../../installers";


@Service()
export class Templates {

  private kurlURL: string;
  private installTmpl: (any) => string;
  private joinTmpl: (any) => string;
  private createBundleScript: string;

  constructor () {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";

    const tmplDir = path.join(__dirname, "../../../../templates");
    const installTmplPath = path.join(tmplDir, "install.tmpl");
    const joinTmplPath = path.join(tmplDir, "join.tmpl");
    const createBundlePath = path.join(tmplDir, "create-bundle-alpine.sh");

    const opts = {
      escape: /{{-([\s\S]+?)}}/g,
      evaluate: /{{([\s\S]+?)}}/g,
      interpolate: /{{=([\s\S]+?)}}/g,
    };
    this.installTmpl = _.template(fs.readFileSync(installTmplPath, "utf8"), opts);
    this.joinTmpl = _.template(fs.readFileSync(joinTmplPath, "utf8"), opts);
    this.createBundleScript = fs.readFileSync(createBundlePath, "utf8");
  }

  public renderInstallScript(i: Installer): string {
    return this.installTmpl(manifestFromInstaller(i, this.kurlURL));
  }

  public renderJoinScript(i: Installer): string {
    return this.joinTmpl(manifestFromInstaller(i, this.kurlURL));
  }

  public renderCreateBundleScript(i: Installer): string {
    return this.createBundleScript;
  }
}

interface Manifest {
  KURL_URL: string;
  INSTALLER_ID: string;
  KUBERNETES_VERSION: string;
  WEAVE_VERSION: string;
  ROOK_VERSION: string;
  CONTOUR_VERSION: string;
}

function manifestFromInstaller(i: Installer, kurlURL: string): Manifest {
  return {
    KURL_URL: kurlURL,
    INSTALLER_ID: i.id,
    KUBERNETES_VERSION: i.kubernetesVersion(),
    WEAVE_VERSION: i.weaveVersion(),
    ROOK_VERSION: i.rookVersion(),
    CONTOUR_VERSION: i.contourVersion(),
  };
}

