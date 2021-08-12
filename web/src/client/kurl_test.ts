import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const spec = `
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
  docker:
    version: latest
  kurl:
    nameserver: 8.8.8.8
`;

const licenseSpec = `
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
  containerd:
    version: latest
  kurl:
    nameserver: 8.8.8.8
    licenseURL: https://raw.githubusercontent.com/replicatedhq/kURL/master/LICENSE
`;

describe("script with kurl config", () => {
	it("200 latest docker", async () => {
		const uri = await client.postInstaller(spec);

		expect(uri).to.match(/dcd3038/);

		const script = await client.getInstallScript("dcd3038");

		expect(script).to.match(new RegExp(`kurl:`));
		expect(script).to.match(new RegExp(`nameserver: 8.8.8.8`));
	});

  it("200 latest containerd with licenseURL", async () => {
		const uri = await client.postInstaller(licenseSpec);
		expect(uri).to.match(/a364191/);

		const script = await client.getInstallScript("a364191");

		expect(script).to.match(new RegExp(`kurl:`));
		expect(script).to.match(new RegExp(`nameserver: 8.8.8.8`));
		expect(script).to.match(new RegExp(`licenseURL: https://raw.githubusercontent.com/replicatedhq/kURL/master/LICENSE`));
	});
});
