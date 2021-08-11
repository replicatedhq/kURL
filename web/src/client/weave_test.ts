import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const weaveDefault = `
apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata: 
  name: weave 
spec: 
  kubernetes: 
    version: 1.19.3 
  weave: 
    version: latest
    noMasqLocal: true
  contour: 
    version: latest
  docker: 
    version: latest
`;

describe("weave default no masq local", () => {
	it("200", async () => {
		const uri = await client.postInstaller(weaveDefault);

		expect(uri).to.match(/5442c72/);

		const script = await client.getInstallScript("5442c72");

		expect(script).to.match(new RegExp(`weave:`));
		expect(script).to.match(new RegExp(`noMasqLocal: true`));
	});
});


