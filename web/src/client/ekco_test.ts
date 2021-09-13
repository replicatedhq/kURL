import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const ekco = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ekco
spec:
  kubernetes:
    version: 1.19.7
  docker:
    version: 19.03.10
  ekco:
    version: 0.12.0
    podImageOverrides:
    - kotsadm/kotsadm:v1.50.2=ttl.sh/areed/kotsadm:12h
    - postgres:10.17-alpine=ttl.sh/areed/potsgres:10.17-alpine
`;

describe("script with ekco config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(ekco);

		expect(uri).to.match(/4fce0b3/);

		const script = await client.getInstallScript("4fce0b3");

		expect(script).to.contain("ekco:");
		expect(script).to.contain("version: 0.12.0");
    expect(script).to.contain("- kotsadm/kotsadm:v1.50.2=ttl.sh/areed/kotsadm:12h");
    expect(script).to.contain("- postgres:10.17-alpine=ttl.sh/areed/potsgres:10.17-alpine");
	});
});
