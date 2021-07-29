import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from ".";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const k3s = `
spec:
  k3s:
    version: v1.19.7+k3s1
`;

describe("script with K3S", () => {
	it("200", async () => {
		const uri = await client.postInstaller(k3s);

		expect(uri).to.match(/b09a2e9/);

		const script = await client.getInstallScript("b09a2e9");

	});
});
