import * as path from "path";

import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from ".";
import * as _ from "lodash";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const rke2 = `
spec:
  rke2:
    version: v1.19.7+rke2r1
`;

describe("script with RKE2", () => {
	it("200", async () => {
		const uri = await client.postInstaller(rke2);

		expect(uri).to.match(/fb713cb/);

		const script = await client.getInstallScript("fb713cb");

	});
});
