import {describe, it} from "mocha";
import {expect} from "chai";
import { bashStringEscape, manifestFromInstaller } from "../../util/services/templates";
import * as _ from "lodash";
import { Installer } from "../../installers";


describe("Escape Bash Special Characters", () => {

  it("escapes select characters", () => {
    const valid= String.raw`
daemonConfig: |
  {
      "double-quotes": ["\backslash", {"exclaimation": "!"}],
  }
`
    const out = bashStringEscape(valid);
    expect(out).to.contain(String.raw`\"double-quotes\": [\"\\backslash\", {\"exclaimation\": \"\!\"}],`);
  });

  // js-yaml will add single quotes to numeric objects to make valid yaml
  it("does not escape single quotes", () => {
    const singleQuotes= String.raw`metadata: '12345678'`
    const out = bashStringEscape(singleQuotes);
    expect(out).to.equal(singleQuotes);
  });

});

describe("When rendering installer yaml", () => {
  it("does not strip double quotes from integers", () => {
    const yaml = `apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: "0668700"
spec:
  kubernetes:
    version: 1.19.9
  docker:
    version: 20.10.5
  weave:
    version: 2.6.5
  rook:
    isBlockStorageEnabled: true
    version: 1.4.3
  prometheus:
    version: 0.46.0
  sonobuoy:
    version: 0.50.0
`;
    const installer = Installer.parse(yaml);

    const manifest = manifestFromInstaller(installer, "KURL_URL", "APP_URL", "DIST_URL", "UTIL_IMAGE", "BINUTILS_IMAGE", "");
    expect(manifest.INSTALLER_YAML).to.contain(`name: '0668700'`);
  });
});
