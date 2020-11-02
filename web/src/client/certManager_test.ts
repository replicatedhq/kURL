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

const certManager = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: certmanager
spec:
  kubernetes:
    version: 1.17.7
  docker:
    version: 19.03.10
  weave:
    version: 2.7.0
  certManager:
    version: 1.0.3
`;

describe("script with certManager config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(certManager);

		expect(uri).to.match(/8db60db/);

		const script = await client.getInstallScript("8db60db");

		expect(script).to.match(new RegExp(`certManager:`));
		expect(script).to.match(new RegExp(`version: 1.0.3`));
	});
});
