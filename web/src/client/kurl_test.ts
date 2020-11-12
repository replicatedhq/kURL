import * as path from "path";
import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";
import { Installer } from "../installers";

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

describe("script with kurl config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(spec);

		expect(uri).to.match(/dcd3038/);

		const script = await client.getInstallScript("dcd3038");

		expect(script).to.match(new RegExp(`kurl:`));
		expect(script).to.match(new RegExp(`nameserver: 8.8.8.8`));
	});
});
