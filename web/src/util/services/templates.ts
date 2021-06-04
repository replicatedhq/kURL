import * as _ from "lodash";
import fetch from "node-fetch";
import { Service } from "ts-express-decorators";
import { Installer } from "../../installers";
import { HTTPError } from "../../server/errors";
import { getDistUrl, getPackageUrl, kurlVersionOrDefault } from "../package";

@Service()
export class Templates {

  private kurlURL: string;
  private distURL: string;
  private replicatedAppURL: string;
  private kurlUtilImage: string;
  private kurlBinUtils: string;
  private installTmplResolved: (data?: object) => string;
  private joinTmplResolved: (data?: object) => string;
  private upgradeTmplResolved: (data?: object) => string;
  private tasksTmplResolved: (data?: object) => string;
  private templateOpts = {
    escape: /{{-([\s\S]+?)}}/g,
    evaluate: /{{([\s\S]+?)}}/g,
    interpolate: /{{=([\s\S]+?)}}/g,
  };

  constructor() {
    this.kurlURL = process.env["KURL_URL"] || "https://kurl.sh";
    this.replicatedAppURL = process.env["REPLICATED_APP_URL"] || "https://replicated.app";
    this.kurlUtilImage = process.env["KURL_UTIL_IMAGE"] || "replicated/kurl-util:alpha";
    this.kurlBinUtils = process.env["KURL_BIN_UTILS_FILE"] || "kurl-bin-utils-latest.tar.gz";

    this.distURL = getDistUrl();
  }

  private async installTmpl(): Promise<((data?: object) => string)> {
    if (this.installTmplResolved) {
      return this.installTmplResolved;
    }
    this.installTmplResolved = await this.tmplFromUpstream("", "install.tmpl");
    return this.installTmplResolved;
  }

  private async joinTmpl(): Promise<((data?: object) => string)> {
    if (this.joinTmplResolved) {
      return this.joinTmplResolved;
    }
    this.joinTmplResolved = await this.tmplFromUpstream("", "join.tmpl");
    return this.joinTmplResolved;
  }

  private async upgradeTmpl(): Promise<((data?: object) => string)> {
    if (this.upgradeTmplResolved) {
      return this.upgradeTmplResolved;
    }
    this.upgradeTmplResolved = await this.tmplFromUpstream("", "upgrade.tmpl");
    return this.upgradeTmplResolved;
  }

  private async tasksTmpl(): Promise<((data?: object) => string)> {
    if (this.tasksTmplResolved) {
      return this.tasksTmplResolved;
    }
    this.tasksTmplResolved = await this.tmplFromUpstream("", "tasks.tmpl");
    return this.tasksTmplResolved;
  }

  public async renderInstallScript(i: Installer, kurlVersion: string|undefined): Promise<string> {
    if (!kurlVersion) {
      return this.renderScriptFromTemplate(i, "", await this.installTmpl());
    }
    return await this.renderScriptFromUpstream(i, kurlVersion, "install.tmpl");
  }

  public async renderJoinScript(i: Installer, kurlVersion: string|undefined): Promise<string> {
    if (!kurlVersion) {
      return this.renderScriptFromTemplate(i, "", await this.joinTmpl());
    }
    return await this.renderScriptFromUpstream(i, kurlVersion, "join.tmpl");
  }

  public async renderUpgradeScript(i: Installer, kurlVersion: string|undefined): Promise<string> {
    if (!kurlVersion) {
      return this.renderScriptFromTemplate(i, "", await this.upgradeTmpl());
    }
    return await this.renderScriptFromUpstream(i, kurlVersion, "upgrade.tmpl");
  }

  public async renderTasksScript(i: Installer, kurlVersion: string|undefined): Promise<string> {
    if (!kurlVersion) {
      return this.renderScriptFromTemplate(i, "", await this.tasksTmpl());
    }
    return await this.renderScriptFromUpstream(i, kurlVersion, "tasks.tmpl");
  }

  public renderScriptFromTemplate(i: Installer, kurlVersion: string, tmpl: (data?: object) => string): string {
    return tmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL, this.distURL, this.kurlUtilImage, this.kurlBinUtils, kurlVersion));
  }

  public async renderScriptFromUpstream(i: Installer, kurlVersion: string, script: string): Promise<string> {
    const tmpl = await this.tmplFromUpstream(kurlVersion, script);
    return tmpl(manifestFromInstaller(i, this.kurlURL, this.replicatedAppURL, this.distURL, this.kurlUtilImage, this.kurlBinUtils, kurlVersion));
  }

  public async tmplFromUpstream(kurlVersion: string, script: string): Promise<((data?: object) => string)> {
    const res = await fetch(getPackageUrl(this.distURL, kurlVersion, script));
    if (res.status === 404) {
      throw new HTTPError(404, "version not found");
    } else if (res.status !== 200) {
      throw new HTTPError(500, `unexpected http status ${res.statusText}`);
    }
    const body = await res.text();
    return _.template(body, this.templateOpts);
  }
}

interface Manifest {
  KURL_URL: string;
  DIST_URL: string;
  INSTALLER_ID: string;
  KURL_VERSION: string;
  REPLICATED_APP_URL: string;
  KURL_UTIL_IMAGE: string;
  KURL_BIN_UTILS_FILE: string;
  STEP_VERSIONS: string;
  INSTALLER_YAML: string;
}

export function bashStringEscape( unescaped : string): string {
  return unescaped.replace(/[!"\\]/g, "\\\$&");
}

export function manifestFromInstaller(i: Installer, kurlURL: string, replicatedAppURL: string, distURL: string, kurlUtilImage: string, kurlBinUtils: string, kurlVersion: string): Manifest {
  kurlVersion = kurlVersionOrDefault(kurlVersion, i);
  if (kurlVersion) {
    kurlUtilImage = `replicated/kurl-util:${kurlVersion}`;
    kurlBinUtils = `kurl-bin-utils-${kurlVersion}.tar.gz`;
  }
  return {
    KURL_URL: kurlURL,
    DIST_URL: distURL,
    INSTALLER_ID: i.id,
    KURL_VERSION: kurlVersion,
    REPLICATED_APP_URL: replicatedAppURL,
    KURL_UTIL_IMAGE: kurlUtilImage,
    KURL_BIN_UTILS_FILE: kurlBinUtils,
    STEP_VERSIONS: `(${Installer.latestMinors().join(" ")})`,
    INSTALLER_YAML: bashStringEscape(i.toYAML()),
  };
}
