import * as _ from "lodash";
import fetch from "node-fetch";
import bugsnag = require("bugsnag");
import { HTTPError } from "../server/errors";
import { getPackageUrl } from "../util/package";
import { InstallerVersions } from "./versions";

interface IInstallerVersions {
  [addon: string]: string[];
}

const installerVersionsCache: { [url: string]: IInstallerVersions } = {};

export async function getInstallerVersions(distUrl: string, kurlVersion?: string): Promise<IInstallerVersions> {
  if (!kurlVersion) {
    return InstallerVersions;
  }
  const url = getPackageUrl(distUrl, kurlVersion, "supported-versions-gen.json");
  if (url in installerVersionsCache && installerVersionsCache[url]) {
    return installerVersionsCache[url];
  }
  const res = await fetch(url);
  if (res.status === 404 || res.status === 403) {
    // older versions did not have support for versioned supported-versions-gen.json
    const err = `Supported versions file not found for ${url}`;
    console.error(err);
    bugsnag.notify(err);

    return InstallerVersions;
  } else if (res.status !== 200) {
    throw new HTTPError(500, `unexpected addon supported versions http status ${res.statusText} from url ${url}`);
  }
  const body = await res.json();
  if (!_.get(body, "supportedVersions.kubernetes") || (body.supportedVersions as IInstallerVersions).kubernetes.length === 0) {
    throw new HTTPError(500, `unexpected addon supported versions response body from url ${url}`);
  }
  installerVersionsCache[url] = body.supportedVersions as IInstallerVersions;
  return installerVersionsCache[url];
}
