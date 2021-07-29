import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const iptables = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: iptables
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
  iptablesConfig:
    iptablesCmds:
      - ["-A", "INPUT", "-p", "TCP", "--dport", "6781", "-j", "DROP"]
      - ["-A", "INPUT", "-p", "TCP", "--dport", "6782", "-j", "DROP"]
      - ["-A", "INPUT", "-p", "TCP", "--dport", "10251", "-j", "DROP"]
      - ["-A", "INPUT", "-p", "TCP", "--dport", "10252", "-j", "DROP"]
      - ["-A", "INPUT", "-p", "TCP", "--dport", "10256", "-j", "DROP"]
    preserveConfig: false
`;

describe("script with iptables config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(iptables);

		expect(uri).to.match(/2e643a0/);

		const script = await client.getInstallScript("2e643a0");

		expect(script).to.match(new RegExp(`iptablesConfig:`));
		expect(script).to.match(new RegExp(`iptablesCmds:`));
		expect(script).to.match(new RegExp(`INPUT`));
		expect(script).to.match(new RegExp(`TCP`));
		expect(script).to.match(new RegExp(`6781`));
		expect(script).to.match(new RegExp(`DROP`));
	});
});
