import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from "./";
import { Installer } from "../installers";
import * as jwt from "jsonwebtoken";
import * as url from "url";
import * as _ from "lodash";


const kurlURL = process.env.KURL_URL || "http://localhost:8092";
const client = new KurlClient(kurlURL);

const latest = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
  rook:
    version: latest
  contour:
    version: latest
`;

const d3a9234 = `
spec:
  kubernetes:
    version: 1.15.1
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0`;

const d3a9234Canonical = `apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "d3a9234"
spec:
  kubernetes:
    version: "1.15.1"
  weave:
    version: "2.5.2"
  rook:
    version: "1.0.4"
  contour:
    version: "0.14.0"`;

const min = `
spec:
  kubernetes:
    version: 1.15.1`;

const badK8sVersion = `
spec:
  kubernetes:
    version: 1.14.99`;

const mixedLatest = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
  rook:
    version: 1.0.4
  contour:
    version: latest
`;

describe("POST /installer", () => {
  describe("latest", () => {
    it(`should return 201 "https://kurl.sh/latest"`, async () => {
      const url = await client.postInstaller(latest);

      expect(url).to.equal(`${kurlURL}/latest`);
    });
  });

	describe("d3a9234", () => {
    it(`should return 201 "https://kurl.sh/d3a9234"`, async () => {
      const url = await client.postInstaller(d3a9234);

      expect(url).to.equal(`${kurlURL}/d3a9234`);
    });
  });

  describe("min", () => {
    it(`should return 201 "https://kurl.sh/6898644"`, async () => {
      const url = await client.postInstaller(min);

      expect(url).to.equal(`${kurlURL}/6898644`);
    });
  });

  describe("empty", () => {
    it("400", async () => {
      let err;

      try {
        await client.postInstaller("");
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("status", 400);
    });
  });

  describe("unsupported Kubernetes version", () => {
    it("400", async () => {
      let err;

      try {
        await client.postInstaller(badK8sVersion);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("status", 400);
    });
  });

  describe("invalid YAML", () => {
    it("400", async() => {
      let err;

      try {
        await client.postInstaller("{{");
      } catch (error) {
        err = error;
      }
      expect(err).to.have.property("status", 400);
    });
  });
});

describe("PUT /installer/<id>", () => {
  describe("valid", () => {
    it("201", async() => {
      const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");

      const url = await client.putInstaller(tkn, "kurl-beta", d3a9234);

      expect(url).to.equal(`${kurlURL}/kurl-beta`);
    });
  });

  describe("invalid name", () => {
    it("400", async() => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
        await client.putInstaller(tkn, "invalid name", d3a9234);
      } catch(error) {
        err = error
      }

      expect(err).to.have.property("status", 400);
    });
  });

  describe("reserved name", () => {
    it("400", async() => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
        await client.putInstaller(tkn, "BETA", d3a9234);
      } catch(error) {
        err = error;
      }

      expect(err).to.have.property("status", 400);
    });
  });

  describe("unauthenticated", () => {
    it("401", async () => {
      let err;

      try {
        await client.putInstaller("Bearer xxx", "kurl-beta", d3a9234)
      } catch(error) {
        err = error;
      }

      expect(err).to.have.property("status", 401);
    });
  });

  describe("forbidden", () => {
    before(async () => {
      const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
      await client.putInstaller(tkn, "kurl-beta", d3a9234);
    });

    it("403", async () => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team2"}, "jwt-signing-key");
        await client.putInstaller(tkn, "kurl-beta", d3a9234);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("status", 403);
    });
  });
});

describe("GET /<installerID>", () => {
  describe("/latest", () => {
    const latest = Installer.latest();

    it(`injects k8s ${latest.kubernetesVersion()}, weave ${latest.weaveVersion()}, rook ${latest.rookVersion()}, contour ${latest.contourVersion()}`, async () => {
      const script = await client.getInstallScript("latest");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="${latest.kubernetesVersion()}"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION="${latest.weaveVersion()}"`));
      expect(script).to.match(new RegExp(`ROOK_VERSION="${latest.rookVersion()}"`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION="${latest.contourVersion()}"`));
      expect(script).to.match(/INSTALLER_ID="latest"/);
    });
  });

  describe("min (/6898644)", () => {
    before(async () => {
      await client.postInstaller(min);
    });

    it("injects k8s 1.15.1 only", async() => {
      const script = await client.getInstallScript("6898644");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="1.15.1"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION=""`));
      expect(script).to.match(new RegExp(`ROOK_VERSION=""`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION=""`));
    });
  });

  describe("mixed latest", () => {
    let id: string;

    before(async () => {
      const installer = await client.postInstaller(mixedLatest);
      id = _.trim(url.parse(installer).path, "/");
    });

    it("resolves all versions", async() => {
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="1.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`ROOK_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION="\\d+.\\d+.\\d+"`));
    });
  });
});

describe("GET /<installerID>/join.sh", () => {
  describe("/latest/join.sh", () => {
    const latest = Installer.latest();

    it(`injects k8s ${latest.kubernetesVersion()}, weave ${latest.weaveVersion()}, rook ${latest.rookVersion()}, contour ${latest.contourVersion()}`, async () => {
      const script = await client.getInstallScript("latest");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="${latest.kubernetesVersion()}"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION="${latest.weaveVersion()}"`));
      expect(script).to.match(new RegExp(`ROOK_VERSION="${latest.rookVersion()}"`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION="${latest.contourVersion()}"`));
    });
  });

  describe("min (/6898644/join.sh)", () => {
    before(async () => {
      await client.postInstaller(min);
    });

    it("injects k8s 1.15.1 only", async() => {
      const script = await client.getJoinScript("6898644");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="1.15.1"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION=""`));
      expect(script).to.match(new RegExp(`ROOK_VERSION=""`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION=""`));
    });
  });
})

describe("GET /installer/<installerID>", () => {
  before(async () => {
    await client.postInstaller(min);
  })

  it("returns installer yaml", async() => {
    const yaml = await client.getInstallerYAML("6898644");

    expect(yaml).to.equal(`apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "6898644"
spec:
  kubernetes:
    version: "1.15.1"
  weave:
    version: ""
  rook:
    version: ""
  contour:
    version: ""
`);
  });

  describe("/installer/latest?resolve=true", () => {
    before(async () => {
      await client.postInstaller(latest);
    });

    it("returns yaml with version", async () => {
      const yaml = await client.getInstallerYAML("latest", true);

      expect(yaml).not.to.match(/version: "latest"/);
    });
  });

  describe("/installer/latest", () => {
    before(async () => {
      await client.postInstaller(latest);
    });

    it(`returns yaml with "latest"`, async () => {
      const yaml = await client.getInstallerYAML("latest");

      expect(yaml).to.match(/version: "latest"/);
    });
  });
});
