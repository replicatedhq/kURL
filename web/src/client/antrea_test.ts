import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const antrea = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: antrea
spec:
  kubernetes:
    version: 1.19.7
  docker:
    version: 19.03.10
  antrea:
    version: 0.13.1
`;

describe("script with antrea config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(antrea);

		expect(uri).to.match(/13a8868/);

		const script = await client.getInstallScript("13a8868");

		expect(script).to.match(new RegExp(`antrea:`));
		expect(script).to.match(new RegExp(`version: 0.13.1`));
	});
});
