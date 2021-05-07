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

const latest = `
apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: latest
  docker:
    version: latest
  weave:
    version: latest
  rook:
    version: latest
  ekco:
    version: latest
  contour:
    version: latest
  registry:
    version: latest
  prometheus:
    version: latest
`;

const latestV1Beta1 = `
apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: latest
  docker:
    version: latest
  weave:
    version: latest
  rook:
    version: latest
  ekco:
    version: latest
  contour:
    version: latest
  registry:
    version: latest
  prometheus:
    version: latest
`;

const nineteen = `
spec:
  kubernetes:
    version: 1.19.9
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0`;

const min = `
spec:
  kubernetes:
    version: 1.19.9`;

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

const badName = `apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "latest"
spec:
  kubernetes:
    version: "1.19.9"
  rook:
    version: "1.0.4"
  contour:
    version: "0.14.0"`;

const kots = `
spec:
  kubernetes:
    version: latest
  kotsadm:
    version: latest
    applicationSlug: sentry-enterprise
`;

const velero = `
spec:
  kubernetes:
    version: latest
  velero:
    version: latest
    namespace: velero
    disableCLI: false
    disableRestic: false
    localBucket: velero
    resticRequiresPrivileged: false
`;

const fluentd = `
spec:
  kubernetes:
    version: latest
  fluentd:
    version: latest
    fullEFKStack: true
`;

const minio = `
spec:
  kubernetes:
    version: latest
  minio:
    version: latest
    namespace: minio
`;

const openebs = `
spec:
  kubernetes:
    version: latest
  openebs:
    version: latest
    namespace: openebs
    isLocalPVEnabled: true
    localPVStorageClassName: default
    isCstorEnabled: true
    cstorStorageClassName: cstor
`;

const ekco = `
spec:
  kubernetes:
    version: latest
  ekco:
    version: latest
    nodeUnreachableToleration: 10m
    minReadyMasterNodeCount: 3
    minReadyWorkerNodeCount: 1
    shouldDisableRebootService: false
    shouldDisableClearNodes: false
    shouldEnablePurgeNodes: false
    rookShouldUseAllNodes: false
`;

const rookBlock = `
spec:
  kubernetes:
    version: latest
  rook:
    version: latest
    isBlockStorageEnabled: true
    blockDeviceFilter: sdb
`;

const proxy = `
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
  docker:
    version: latest
  kurl:
    proxyAddress: http://proxy.internal:3128
    additionalNoProxyAddresses:
    - registry.internal
    - 10.128.0.44
    noProxy: false
`;

const contour = `
spec:
  kubernetes:
    version: latest
  contour:
    version: latest
    httpPort: 3080
    httpsPort: 3443
`;

const overrideUnknownVersion = `
spec:
  kubernetes:
    version: latest
  contour:
    version: 100.0.0
    tlsMinimumProtocolVersion: "1.3"
    s3Override: https://dummy.s3.us-east-1.amazonaws.com/pr/contour-100.0.0.tar.gz
`;

const overrideKnownVersion = `
spec:
  kubernetes:
    version: latest
  contour:
    version: latest
    tlsMinimumProtocolVersion: "1.3"
    s3Override: https://dummy.s3.us-east-1.amazonaws.com/pr/contour-100.0.0.tar.gz
`;

const helm = `
spec:
  kubernetes:
    version: latest
  helm:
    helmfileSpec: |
      repositories:
      - name: nginx-stable
        url: https://helm.nginx.com/stable
      releases:
      - name: test-nginx-ingress
        chart: nginx-stable/nginx-ingress
        values:
        - controller:
            service:
              type: NodePort
              httpPort:
                nodePort: 30080
              httpsPort:
                nodePort: 30443
    additionalImages:
    - postgres
`;

const pinnedMinork8s = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: 1.18.x
`;

describe("POST /installer", () => {
  describe("latestV1Beta1", () => {
    it(`should return 201 "https://kurl.sh/latest"`, async () => {
      const uri = await client.postInstaller(latestV1Beta1);

      expect(uri).to.match(/latest$/);
    });
  });

  describe("incorrect name", () => {
    it("should be ignored", async () => {
      await client.postInstaller(badName);
    });
  });

  describe("3b657c6", () => {
    it(`should return 201 "https://kurl.sh/3b657c6"`, async () => {
      const uri = await client.postInstaller(nineteen);

      expect(uri).to.match(/3b657c6/);
    });
  });

  describe("min", () => {
    it(`should return 201 "https://kurl.sh/d44632a"`, async () => {
      const uri = await client.postInstaller(min);

      expect(uri).to.match(/d44632a/);
    });
  });

  describe("fluentd", () => {
    it(`should return 201 "https://kurl.sh/472aa23"`, async () => {
      const uri = await client.postInstaller(fluentd);

      expect(uri).to.match(/472aa23/);
    });
  });

  describe("kots", () => {
    it(`should return 201 "https://kurl.sh/4a39417"`, async () => {
      const uri = await client.postInstaller(kots);

      expect(uri).to.match(/4a39417/);
    });
  });

  describe("velero", () => {
    it(`should return 201 "htps://kurl.sh/09e8b98"`, async () => {
      const uri = await client.postInstaller(velero);

      expect(uri).to.match(/09e8b98/);
    });
  });

  describe("minio", () => {
    it(`should return 201 "https://kurl.sh/d2de354"`, async () => {
      const uri = await client.postInstaller(minio);

      expect(uri).to.match(/d2de354/);
    });
  });

  describe("openebs", () => {
    it(`should return 201 "https://kurl.sh/070e1fa"`, async () => {
      const uri = await client.postInstaller(openebs);

      expect(uri).to.match(/070e1fa/);
    });
  });

  describe("ekco", () => {
    it(`should return 201 "https://kurl.sh/bf0b204"`, async () => {
      const uri = await client.postInstaller(ekco);

      expect(uri).to.match(/bf0b204/);
    });
  });

  describe("contour", () => {
    it(`should return 201 "https://kurl.sh/ee30416"`, async () => {
      const uri = await client.postInstaller(contour);

      expect(uri).to.match(/ee30416/);
    });
  });


  describe("Helm with nginx (/4077ac3)", () => {
    it(`should return 201 "https://kurl.sh/4077ac3"`, async () => {
      const uri = await client.postInstaller(helm);

      expect(uri).to.match(/4077ac3/);
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

      expect(err).to.have.property("message", "Kubernetes version is required");
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

      expect(err).to.have.property("message", "Kubernetes version 1.14.99 is not supported");
    });
  });

  describe("invalid YAML", () => {
    it("400", async () => {
      let err;

      try {
        await client.postInstaller("{{");
      } catch (error) {
        err = error;
      }
      expect(err).to.have.property("message", "YAML could not be parsed");
    });
  });

  describe("unknown version with override", () => {
    it(`should return 201 "https://kurl.sh/873e13e"`, async () => {
      const uri = await client.postInstaller(overrideUnknownVersion);

      expect(uri).to.match(/873e13e/);
    });
  });

  describe("latest version with override", () => {
    it(`should return 201 "https://kurl.sh/0ea78e6 instead of "latest"`, async () => {
      const uri = await client.postInstaller(overrideKnownVersion);

      expect(uri).to.match(/0ea78e6/);
    });
  });
});

describe("PUT /installer/<id>", () => {
  describe("valid", () => {
    it("201", async () => {
      const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
      const uri = await client.putInstaller(tkn, "kurl-beta", nineteen);

      expect(uri).to.match(/kurl-beta/);
    });
  });

  describe("invalid name", () => {
    it("400", async () => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
        await client.putInstaller(tkn, "invalid name", nineteen);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("message", "Only base64 URL characters may be used for custom named installers");
    });
  });

  describe("reserved name", () => {
    it("400", async () => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
        await client.putInstaller(tkn, "BETA", nineteen);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("message", "The requested custom installer name is reserved");
    });
  });

  describe("unauthenticated", () => {
    it("401", async () => {
      let err;

      try {
        await client.putInstaller("Bearer xxx", "kurl-beta", nineteen);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("message", "Authentication required");
    });
  });

  describe("forbidden", () => {
    before(async () => {
      const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
      await client.putInstaller(tkn, "kurl-beta", nineteen);
    });

    it("403", async () => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team2"}, "jwt-signing-key");
        await client.putInstaller(tkn, "kurl-beta", nineteen);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("status", 403);
    });
  });
});

describe("GET /<installerID>", () => {
  describe("/latest", () => {
    const latestResolve = Installer.latest().resolve();

    it(`injects k8s ${latestResolve.spec.kubernetes.version}, weave ${latestResolve.spec.weave!.version}, rook ${latestResolve.spec.rook!.version}, contour ${latestResolve.spec.contour!.version}, registry ${latestResolve.spec.registry!.version}, prometheus ${latestResolve.spec.prometheus!.version}, docker ${latestResolve.spec.docker!.version}`, async () => {
      const script = await client.getInstallScript("latest");

      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.kubernetes.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.weave!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.rook!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.ekco!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.contour!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.registry!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.prometheus!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.docker!.version}`));
      expect(script).to.match(/INSTALLER_ID="latest"/);
    });
  });

  describe("min (/d44632a)", () => {
    before(async () => {
      await client.postInstaller(min);
    });

    it("injects k8s 1.19.9 only", async () => {
      const script = await client.getInstallScript("d44632a");

      expect(script).to.match(new RegExp(`version: 1.19.9`));
    });
  });

  describe("mixed latest", () => {
    let id: string;

    before(async () => {
      const installer = await client.postInstaller(mixedLatest);
      id = _.trim(url.parse(installer).path, "/");
    });

    it("resolves all versions", async () => {
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: \\d+.\\d+.\\d+`));
      expect(script).not.to.match(new RegExp(`version: latest`));
    });
  });

  describe("velero (/09e8b98)", () => {
    const id = "09e8b98";
    before(async () => {
      const uri = await client.postInstaller(velero);
      expect(uri).to.match(/09e8b98/);
    });

    it("injects velero version and flags", async () => {
      const i = Installer.parse(velero);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: ${i.resolve().spec.velero!.version}`));
    });
  });

  describe("minio (/d2de354)", () => {
    const id = "d2de354";

    before(async () => {
      const uri = await client.postInstaller(minio);
      expect(uri).to.match(/d2de354/);
    });

    it("injects minio version and flags", async () => {
      const i = Installer.parse(minio);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: ${i.resolve().spec.minio!.version}`));
    });
  });

  describe("openebs (/070e1fa)", () => {
    const id = "070e1fa";

    before(async () => {
      const uri = await client.postInstaller(openebs);
      expect(uri).to.match(/070e1fa/);
    });

    it("injects openebs version and flags", async () => {
      const i = Installer.parse(openebs);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: ${i.resolve().spec.openebs!.version}`));
    });
  });

  describe("ekco (/bf0b204)", () => {
    const id = "bf0b204";

    before(async () => {
      const uri = await client.postInstaller(ekco);
      expect(uri).to.match(/bf0b204/);
    });

    it("injects ekco version and flags", async () => {
      const i = Installer.parse(ekco);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: ${i.resolve().spec.ekco!.version}`));
    });
  });

  describe("rook with block storage (/1a1b590)", () => {
    const id = "1a1b590";

    before(async () => {
      const uri = await client.postInstaller(rookBlock);
      expect(uri).to.match(new RegExp(id));
    });

    it("injects rook block storage configuration flags", async () => {
      const i = Installer.parse(rookBlock);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: ${i.resolve().spec.rook!.version}`));
    });
  });

  describe("proxy (/5797a35)", () => {
    const id = "5797a35";

    before(async () => {
      const uri = await client.postInstaller(proxy);
      expect(uri).to.match(new RegExp(id));
    });

    it("configures proxies", async () => {
      const i = Installer.parse(proxy);

      const script = await client.getInstallScript(id);
      expect(script).to.have.string("proxyAddress: http://proxy.internal:3128");
      expect(script).to.have.string("registry.internal");
      expect(script).to.have.string("10.128.0.44");
      expect(script).to.have.string("noProxy: false");
    });
  });

  describe("known versions with override (/873e13e)", () => {
    before(async () => {
      const url = await client.postInstaller(overrideUnknownVersion);
      console.log(url);
    });

    it("returns override", async () => {
      const script = await client.getInstallScript("873e13e");

      expect(script).to.match(new RegExp(`s3Override: https://dummy.s3.us-east-1.amazonaws.com/pr/contour-100.0.0.tar.gz`));
    });
  });
});

describe("GET /<installerID>/join.sh", () => {
  describe("/latest/join.sh", () => {
    const latestResolve = Installer.latest().resolve();

    it(`injects k8s ${latestResolve.spec.kubernetes.version}, weave ${latestResolve.spec.weave!.version}, rook ${latestResolve.spec.rook!.version}, contour ${latestResolve.spec.contour!.version}, registry ${latestResolve.spec.registry!.version}, prometheus ${latestResolve.spec.prometheus!.version}`, async () => {
      const script = await client.getJoinScript("latest");

      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.kubernetes.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.weave!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.rook!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.ekco!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.contour!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.registry!.version}`));
      expect(script).to.match(new RegExp(`version: ${latestResolve.spec.prometheus!.version}`));
    });
  });

  describe("min (/d44632a/join.sh)", () => {
    before(async () => {
      await client.postInstaller(min);
    });

    it("injects k8s 1.19.9 only", async () => {
      const script = await client.getJoinScript("d44632a");

      expect(script).to.match(new RegExp(`version: 1.19.9`));
    });
  });

  describe("kots (/4a39417)", () => {
    before(async () => {
      await client.postInstaller(kots);
    });

    it("injests KOTSADM_APPLICATION_SLUG", async () => {
      const script = await client.getInstallScript("4a39417");

      expect(script).to.match(new RegExp(`applicationSlug: sentry-enterprise`));
    });
  });
});

describe("GET /installer/<installerID>", () => {
  before(async () => {
    const uri = await client.postInstaller(min);
  });

  it("returns installer yaml", async () => {
    const yaml = await client.getInstallerYAML("d44632a");

    expect(yaml).to.equal(`apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: d44632a
spec:
  kubernetes:
    version: 1.19.9
`);
  });

  describe("/installer/latest?resolve=true", () => {
    before(async () => {
      await client.postInstaller(latest);
    });

    it("returns yaml with version", async () => {
      const yaml = await client.getInstallerYAML("latest", true);

      expect(yaml).not.to.match(/version: latest/);
    });

    it("does not return a name", async () => {
      const yaml = await client.getInstallerYAML("latest", true);

      expect(yaml).to.match(/name: ''/);
    });
  });

  describe("/installer/latest", () => {
    before(async () => {
      await client.postInstaller(latest);
    });

    it(`returns yaml with "latest"`, async () => {
      const yaml = await client.getInstallerYAML("latest");

      expect(yaml).to.match(/version: latest/);
    });

    describe("Accpet: application/json", () => {
      it("returns json", async () => {
        const obj = await client.getInstallerJSON("latest");

        expect(obj.spec.kubernetes).to.have.property("version", "latest");
      });
    });
  });
});

describe("GET /installer", () => {
  it("returns all available package and addon versions", async () => {
    const versions = await client.getVersions();

    expect(versions.kubernetes).to.be.an.instanceof(Array);
    expect(versions.kubernetes).to.contain("1.19.9");
    expect(versions.kubernetes).to.contain("latest");
    expect(versions.kubernetes).to.contain("1.16.4");
    expect(versions.weave).to.contain("2.5.2");
    expect(versions.weave).to.contain("latest");
    expect(versions.rook).to.contain("1.0.4");
    expect(versions.rook).to.contain("latest");
    expect(versions.ekco).to.contain("0.3.0");
    expect(versions.ekco).to.contain("latest");
    expect(versions.contour).to.contain("0.14.0");
    expect(versions.contour).to.contain("latest");
    expect(versions.registry).to.contain("latest");
    expect(versions.registry).to.contain("2.7.1");
    expect(versions.prometheus).to.contain("latest");
    expect(versions.prometheus).to.contain("0.33.0");
    expect(versions.kotsadm).to.contain("0.9.9");
  });
});

describe("POST /installer/validate", () => {
  describe("latestV1Beta1", () => {
    it(`should return 200 ""`, async () => {
      const res = await client.validateInstaller(latestV1Beta1);

      expect(res).to.equal("");
    });
  });

  describe("empty", () => {
    it("400", async () => {
      let err;

      try {
        await client.validateInstaller("");
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("message", "Kubernetes version is required");
    });
  });

  describe("unsupported Kubernetes version", () => {
    it("400", async () => {
      let err;

      try {
        await client.validateInstaller(badK8sVersion);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("message", "Kubernetes version 1.14.99 is not supported");
    });
  });

  describe("invalid YAML", () => {
    it("400", async () => {
      let err;

      try {
        await client.validateInstaller("{{");
      } catch (error) {
        err = error;
      }
      expect(err).to.have.property("message", "YAML could not be parsed");
    });
  });

  describe("pinned minor k8s version", () => {
    let id: string;

    before(async () => {
      const installer = await client.postInstaller(pinnedMinork8s);
      id = _.trim(url.parse(installer).path, "/");
    });

    it("resolves all versions", async () => {
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`version: 1.18.\\d+`));
      expect(script).not.to.match(new RegExp(`version: 1.18.x`));
    });
  });

  describe("rook 1.0.4 with Kubernetes 1.20.0", () => {
    it("400", async () => {
      const spec = `
      spec:
        rook:
          version: 1.0.4
        kubernetes:
          version: 1.20.0`;
      let err;

      try {
        await client.validateInstaller(spec);
      } catch (error) {
        err = error;
      }
      expect(err).to.have.property("message", "Rook 1.0.4 is not compatible with Kubernetes 1.20+");
    });
  });
});
