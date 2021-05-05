
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
  if (process.env["KURL_VERSION"]) {
    distUrl += `/${process.env["KURL_VERSION"]}`;
  }
  return distUrl;
}
