import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const latest = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ignored
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
  rook:
    version: latest
  contour:
    version: latest
`;

const d3a9234 = `
spec:
  kubernetes:
    version: 1.15.1
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0`

const d3a9234Canonical = `apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "d3a9234"
spec:
  kubernetes:
    version: "1.15.1"
  weave:
    version: "2.5.2"
  rook:
    version: "1.0.4"
  contour:
    version: "0.14.0"`

const min = `
spec:
  kubernetes:
    version: 1.15.1`

describe("POST /installer", () => {
  const kurlURL = process.env.KURL_URL || "http://localhost:8092";

  const client = new KurlClient(kurlURL);

  describe("latest", () => {
    it(`should return 201 "https://kurl.sh/latest"`, async () => {
      const url = await client.postInstaller(latest);

      expect(url).to.equal(`${kurlURL}/latest`);
    });
  });

	describe("d3a9234", () => {
    it(`should return 201 "https://kurl.sh/d3a9234"`, async () => {
      const url = await client.postInstaller(d3a9234);

      expect(url).to.equal(`${kurlURL}/d3a9234`);
    });
  });

  describe("min", () => {
    it(`should return 201 "https://kurl.sh/6898644"`, async () => {
      const url = await client.postInstaller(min);

      expect(url).to.equal(`${kurlURL}/6898644`);
    });
  });
});
