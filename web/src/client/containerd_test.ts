import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const containerd = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: containerd
spec:
  kubernetes:
    version: 1.21.1
  containerd:
    version: 1.4.4
    tomlConfig: |
      [timeouts]
        "io.containerd.shim-timeout": "15s"
  antrea:
    version: 0.13.1
`;

describe("script with containerd toml config", () => {
  it("200", async () => {
    const uri = await client.postInstaller(containerd);

    expect(uri).to.match(/66f6a6e/);

    const script = await client.getInstallScript("66f6a6e");

    expect(script).to.match(new RegExp(`containerd:`));
    expect(script).to.match(new RegExp(`version: 1.4.4`));
    expect(script).to.include(`\\"io.containerd.shim-timeout\\": \\"15s\\"`);
  });
});
