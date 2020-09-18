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

const firewalld = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: firewalld
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
  firewalldConfig:
    firewalld: enabled
    firewalldCmds:
      - ["--zone=home", "--change-interface=eth0"]
    bypassFirewalldWarning: true
    disableFirewalld: false
    hardFailOnFirewalld: false
    preserveConfig: false
`;

describe("script with firewalld config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(firewalld);

		expect(uri).to.match(/02f9d2e/);

		const script = await client.getInstallScript("02f9d2e");

		expect(script).to.match(new RegExp(`firewalldConfig:`));
		expect(script).to.match(new RegExp(`firewalld: enabled`));
		expect(script).to.match(new RegExp(`firewalldCmds:`));
		expect(script).to.match(new RegExp(`zone=home`));
		expect(script).to.match(new RegExp(`change-interface`));
		expect(script).to.match(new RegExp(`bypassFirewalldWarning`));
		expect(script).to.match(new RegExp(`hardFailOnFirewalld: false`));
		expect(script).to.match(new RegExp(`preserveConfig: false`));
	});
});
