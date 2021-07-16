import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const minio = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: minio
spec:
  kubernetes:
    version: 1.19.7
  docker:
    version: 19.03.10
  minio:
    version: 2020-01-25T02-50-51Z
    migrateFromRGW: true
`;

describe("script with minio config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(minio);

		expect(uri).to.match(/b737e21/);

		const script = await client.getInstallScript("b737e21");

		expect(script).to.match(new RegExp(`minio:`));
		expect(script).to.match(new RegExp(`version: 2020-01-25T02-50-51Z`));
		expect(script).to.match(new RegExp(`migrateFromRGW: true`));
	});
});
