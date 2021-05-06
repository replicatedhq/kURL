
export function getPackageUrl(distUrl: string, kurlVersion: string|undefined, pkg: string): string {
  const kv = kurlVersionOrDefault(kurlVersion)
  return `${distUrl}/${kv && `${kv}/`}${pkg}`;
}

export function getDistUrl(): string {
  if (process.env["DIST_URL"]) {
    return process.env["DIST_URL"] as string;
  }
  let distUrl = `https://${process.env["KURL_BUCKET"]}.s3.amazonaws.com`;
  if (process.env["NODE_ENV"] === "production") {
    distUrl += "/dist";
  } else {
    distUrl += "/staging";
  }
  return distUrl;
}

export function kurlVersionOrDefault(kurlVersion?: string): string {
  return kurlVersion || process.env["KURL_VERSION"] || ""
}
