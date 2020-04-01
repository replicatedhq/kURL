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
  contour:
    version: latest
  registry:
    version: latest
  prometheus:
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

const badName = `apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "latest"
spec:
  kubernetes:
    version: "1.15.1"
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
    localBucket: velero
    disableCLI: false
    disableRestic: false
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
    nodeUnreachableTolerationDuration: 10m
    minReadyMasterNodeCount: 3
    minReadyWorkerNodeCount: 1
    shouldDisableRebootService: false
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

  describe("d3a9234", () => {
    it(`should return 201 "https://kurl.sh/d3a9234"`, async () => {
      const uri = await client.postInstaller(d3a9234);

      expect(uri).to.match(/d3a9234$/);
    });
  });

  describe("min", () => {
    it(`should return 201 "https://kurl.sh/6898644"`, async () => {
      const uri = await client.postInstaller(min);

      expect(uri).to.match(/6898644$/);
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
    it(`should return 201 "htps://kurl.sh/b423f81"`, async () => {
      const uri = await client.postInstaller(velero);

      expect(uri).to.match(/b423f81/);
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
    it(`should return 201 "https://kurl.sh/47c84b2"`, async () => {
      const uri = await client.postInstaller(ekco);

      expect(uri).to.match(/47c84b2/);
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
});

describe("PUT /installer/<id>", () => {
  describe("valid", () => {
    it("201", async () => {
      const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
      const uri = await client.putInstaller(tkn, "kurl-beta", d3a9234);

      expect(uri).to.match(/kurl-beta/);
    });
  });

  describe("invalid name", () => {
    it("400", async () => {
      let err;

      try {
        const tkn = jwt.sign({team_id: "team1"}, "jwt-signing-key");
        await client.putInstaller(tkn, "invalid name", d3a9234);
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
        await client.putInstaller(tkn, "BETA", d3a9234);
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
        await client.putInstaller("Bearer xxx", "kurl-beta", d3a9234);
      } catch (error) {
        err = error;
      }

      expect(err).to.have.property("message", "Authentication required");
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
    const latestResolve = Installer.latest().resolve();

    it(`injects k8s ${latestResolve.spec.kubernetes.version}, weave ${latestResolve.spec.weave!.version}, rook ${latestResolve.spec.rook!.version}, contour ${latestResolve.spec.contour!.version}, registry ${latestResolve.spec.registry!.version}, prometheus ${latestResolve.spec.prometheus!.version}, docker ${latestResolve.spec.docker!.version}`, async () => {
      const script = await client.getInstallScript("latest");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="${latestResolve.spec.kubernetes.version}"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION="${latestResolve.spec.weave!.version}"`));
      expect(script).to.match(new RegExp(`ROOK_VERSION="${latestResolve.spec.rook!.version}"`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION="${latestResolve.spec.contour!.version}"`));
      expect(script).to.match(new RegExp(`REGISTRY_VERSION="${latestResolve.spec.registry!.version}"`));
      expect(script).to.match(new RegExp(`PROMETHEUS_VERSION="${latestResolve.spec.prometheus!.version}"`));
      expect(script).to.match(new RegExp(`DOCKER_VERSION="${latestResolve.spec.docker!.version}"`));
      expect(script).to.match(/INSTALLER_ID="latest"/);
      expect(script).to.match(/KOTSADM_VERSION=""/);
      expect(script).to.match(/KOTSADM_APPLICATION_SLUG=""/);
      expect(script).to.match(/MINIO_VERSION=""/);
      expect(script).to.match(/OPENEBS_VERSION=""/);
      expect(script).to.match(/EKCO_VERSION=""/);
    });
  });

  describe("min (/6898644)", () => {
    before(async () => {
      await client.postInstaller(min);
    });

    it("injects k8s 1.15.1 only", async () => {
      const script = await client.getInstallScript("6898644");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="1.15.1"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION=""`));
      expect(script).to.match(new RegExp(`ROOK_VERSION=""`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_APPLICATION_SLUG=""`));
      expect(script).to.match(/MINIO_VERSION=""/);
      expect(script).to.match(/OPENEBS_VERSION=""/);
      expect(script).to.match(/EKCO_VERSION=""/);
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

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="1.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`ROOK_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`KOTSADM_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_APPLICATION_SLUG=""`));
      expect(script).to.match(/MINIO_VERSION=""/);
      expect(script).to.match(/OPENEBS_VERSION=""/);
      expect(script).to.match(/EKCO_VERSION=""/);
    });
  });

  describe("flags", () => {
    let id: string;
    const yaml = `
spec:
  kubernetes:
    version: latest
    serviceCIDR: 10.0.0.0/12`;

    before(async () => {
      const installer = await client.postInstaller(yaml);
      id = _.trim(url.parse(installer).path, "/");
    });

    it("injects flags for advanced options", async () => {
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`FLAGS="service-cidr=10.0.0.0/12"`));
    });
  });

  describe("velero (/b423f81)", () => {
    const id = "b423f81";
    before(async () => {
      const uri = await client.postInstaller(velero);
      expect(uri).to.match(/b423f81/);
    });

    it("injects velero version and flags", async () => {
      const i = Installer.parse(velero);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`VELERO_VERSION="${i.resolve().spec.velero!.version}"`));
      expect(script).to.match(new RegExp(`FLAGS="velero-namespace=velero velero-local-bucket=velero velero-disable-cli=0 velero-disable-restic=0"`));
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

      expect(script).to.match(new RegExp(`MINIO_VERSION="${i.resolve().spec.minio!.version}"`));
      expect(script).to.match(/OPENEBS_VERSION=""/);
      expect(script).to.match(new RegExp(`FLAGS="minio-namespace=minio"`));
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

      expect(script).to.match(new RegExp(`OPENEBS_VERSION="${i.resolve().spec.openebs!.version}"`));
      expect(script).to.match(new RegExp(`FLAGS="openebs-namespace=openebs openebs-localpv-enabled=1 openebs-localpv-storage-class-name=default openebs-cstor-enabled=1 openebs-cstor-storage-class-name=cstor"`));
    });
  });

  describe("ekco (/47c84b2)", () => {
    const id = "47c84b2";

    before(async () => {
      const uri = await client.postInstaller(ekco);
      expect(uri).to.match(/47c84b2/);
    });

    it("injects ekco version and flags", async () => {
      const i = Installer.parse(ekco);
      const script = await client.getInstallScript(id);

      expect(script).to.match(new RegExp(`EKCO_VERSION="${i.resolve().spec.ekco!.version}"`));
      expect(script).to.match(new RegExp(`FLAGS="ekco-node-unreachable-toleration-duration=10m ekco-min-ready-master-node-count=3 ekco-min-ready-worker-node-count=1 ekco-should-disable-reboot-service=0 ekco-rook-should-use-all-nodes=0"`));
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

      expect(script).to.match(new RegExp(`ROOK_VERSION="${i.resolve().spec.rook!.version}"`));
      expect(script).to.match(new RegExp(`FLAGS="rook-block-storage-enabled=1 rook-block-device-filter=sdb"`));
    });
  });
});

describe("GET /<installerID>/join.sh", () => {
  describe("/latest/join.sh", () => {
    const latestResolve = Installer.latest().resolve();

    it(`injects k8s ${latestResolve.spec.kubernetes.version}, weave ${latestResolve.spec.weave!.version}, rook ${latestResolve.spec.rook!.version}, contour ${latestResolve.spec.contour!.version}, registry ${latestResolve.spec.registry!.version}, prometheus ${latestResolve.spec.prometheus!.version}`, async () => {
      const script = await client.getJoinScript("latest");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="${latestResolve.spec.kubernetes.version}"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION="${latestResolve.spec.weave!.version}"`));
      expect(script).to.match(new RegExp(`ROOK_VERSION="${latestResolve.spec.rook!.version}"`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION="${latestResolve.spec.contour!.version}"`));
      expect(script).to.match(new RegExp(`REGISTRY_VERSION="${latestResolve.spec.registry!.version}"`));
      expect(script).to.match(new RegExp(`PROMETHEUS_VERSION="${latestResolve.spec.prometheus!.version}"`));
      expect(script).to.match(new RegExp(`KOTSADM_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_APPLICATION_SLUG=""`));
      expect(script).to.match(/MINIO_VERSION=""/);
      expect(script).to.match(/OPENEBS_VERSION=""/);
      expect(script).to.match(/EKCO_VERSION=""/);
    });
  });

  describe("min (/6898644/join.sh)", () => {
    before(async () => {
      await client.postInstaller(min);
    });

    it("injects k8s 1.15.1 only", async () => {
      const script = await client.getJoinScript("6898644");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="1.15.1"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION=""`));
      expect(script).to.match(new RegExp(`ROOK_VERSION=""`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION=""`));
      expect(script).to.match(new RegExp(`REGISTRY_VERSION=""`));
      expect(script).to.match(new RegExp(`PROMETHEUS_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_APPLICATION_SLUG=""`));
    });
  });

  describe("kots (/4a39417)", () => {
    before(async () => {
      await client.postInstaller(kots);
    });

    it("injests KOTSADM_VERSION and KOTSADM_APPLICATION_SLUG", async () => {
      const script = await client.getInstallScript("4a39417");

      expect(script).to.match(new RegExp(`KUBERNETES_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`WEAVE_VERSION=""`));
      expect(script).to.match(new RegExp(`ROOK_VERSION=""`));
      expect(script).to.match(new RegExp(`CONTOUR_VERSION=""`));
      expect(script).to.match(new RegExp(`REGISTRY_VERSION=""`));
      expect(script).to.match(new RegExp(`PROMETHEUS_VERSION=""`));
      expect(script).to.match(new RegExp(`KOTSADM_VERSION="\\d+.\\d+.\\d+"`));
      expect(script).to.match(new RegExp(`KOTSADM_APPLICATION_SLUG="sentry-enterprise"`));
    });
  });
});

describe("GET /installer/<installerID>", () => {
  before(async () => {
    const uri = await client.postInstaller(min);
  });

  it("returns installer yaml", async () => {
    const yaml = await client.getInstallerYAML("6898644");

    expect(yaml).to.equal(`apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: '6898644'
spec:
  kubernetes:
    version: 1.15.1
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
    expect(versions.kubernetes).to.contain("1.15.3");
    expect(versions.kubernetes).to.contain("latest");
    expect(versions.kubernetes).to.contain("1.15.0");
    expect(versions.weave).to.contain("2.5.2");
    expect(versions.weave).to.contain("latest");
    expect(versions.rook).to.contain("1.0.4");
    expect(versions.rook).to.contain("latest");
    expect(versions.contour).to.contain("0.14.0");
    expect(versions.contour).to.contain("latest");
    expect(versions.registry).to.contain("latest");
    expect(versions.registry).to.contain("2.7.1");
    expect(versions.prometheus).to.contain("latest");
    expect(versions.prometheus).to.contain("0.33.0");
    expect(versions.kotsadm).to.contain("0.9.9");
  });
});
