import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const selinux = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: selinux
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
  selinuxConfig:
    selinux: "permissive"
    type: "targeted"
    semanageCmds:
      - [user, -a, -R, "staff_r sysadm_r system_r", -r, "s0-s0:c0.c1023", my_staff_u]
    chconCmds:
      - ["-v", "--type=httpd_sys_content_t", "/html"]
    preserveConfig: false
    disableSelinux: false
`;

describe("script with selinux config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(selinux);

		expect(uri).to.match(/9ca2f44/);

		const script = await client.getInstallScript("9ca2f44");

		expect(script).to.match(new RegExp(`selinuxConfig`));
		expect(script).to.match(new RegExp(`selinux: permissive`));
		expect(script).to.match(new RegExp(`type: targeted`));
		expect(script).to.match(new RegExp(`semanageCmds:`));
		expect(script).to.match(new RegExp(`sysadm_r`));
		expect(script).to.match(new RegExp(`my_staff_u`));
		expect(script).to.match(new RegExp(`chconCmds`));
		expect(script).to.match(new RegExp(`httpd_sys_content_t`));
		expect(script).to.match(new RegExp(`preserveConfig`));
		expect(script).to.match(new RegExp(`disableSelinux`));
	});
});
