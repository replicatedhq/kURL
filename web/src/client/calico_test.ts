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

const calico = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: calico
spec:
  kubernetes:
    version: 1.17.7
  docker:
    version: 19.03.10
  weave:
    version: 2.7.0
  rook:
    version: 1.4.3
    isBlockStorageEnabled: true
  registry:
    version: 2.7.1
  kotsadm:
    version: 1.19.2
  ekco:
    version: 0.3.0
  calico:
    version: 3.9.1
`;

describe("script with calico config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(calico);

		expect(uri).to.match(/ccfc89b/);

		const script = await client.getInstallScript("ccfc89b");

		expect(script).to.match(new RegExp(`calico:`));
		expect(script).to.match(new RegExp(`version: 3.9.1`));
	});
});
