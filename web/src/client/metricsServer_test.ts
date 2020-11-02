import * as path from "path";

import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";
import { Installer } from "../installers";
import * as jwt from "jsonwebtoken";
import * as url from "url";
import * as _ from "lodash";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const metricsServer = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: metricsserver
spec:
  kubernetes:
    version: 1.17.7
  docker:
    version: 19.03.10
  weave:
    version: 2.7.0
  metricsServer:
    version: 0.3.7
`;

describe("script with metricsServer config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(metricsServer);

		expect(uri).to.match(/3aa6e9e/);

		const script = await client.getInstallScript("3aa6e9e");

		expect(script).to.match(new RegExp(`metricsServer:`));
		expect(script).to.match(new RegExp(`version: 0.3.7`));
	});
});
