import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const sonobuoy = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: sonobuoy
spec:
  kubernetes:
    version: 1.17.7
  docker:
    version: 19.03.10
  weave:
    version: 2.7.0
  sonobuoy:
    version: 0.50.0
`;

describe("script with sonobuoy config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(sonobuoy);

		expect(uri).to.match(/42e4a56/);

		const script = await client.getInstallScript("42e4a56");

		expect(script).to.match(new RegExp(`sonobuoy:`));
		expect(script).to.match(new RegExp(`version: 0.50.0`));
	});
});
