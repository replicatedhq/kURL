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
    version: latest
    isEncryptionDisabled: true
    podCidrRange: /16
    podCIDR: 172.19.0.0/16
`;

describe("script with calico config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(calico);

		expect(uri).to.match(/0bf637c/);

		const script = await client.getInstallScript("0bf637c");

		expect(script).to.match(new RegExp(`calico:`));
		expect(script).to.match(new RegExp("version: "+Installer.versions.calico[0]));
		expect(script).to.match(new RegExp(`isEncryptionDisabled: true`));
		expect(script).to.match(new RegExp(`podCidrRange: /16`));
		expect(script).to.match(new RegExp(`podCIDR: 172.19.0.0/16`));
	});
});
