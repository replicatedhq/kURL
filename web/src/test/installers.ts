import {describe, it} from "mocha";
import {expect} from "chai";
import { Installer } from "../installers";
import * as _ from "lodash";

const everyOption = `apiVersion: kurl.sh/v1beta1
metadata:
  name: everyOption
spec:
  kubernetes:
    version: latest
    serviceCidrRange: /12
    serviceCIDR: 100.1.1.1/12
    haCluster: false
    masterAddress: 192.168.1.1
    loadBalancerAddress: 10.128.10.1
    bootstrapToken: token
    bootstrapTokenTTL: 10min
    kubeadmTokenCAHash: hash
    controlPlane: false
    certKey: key
  docker:
    version: latest
    bypassStorageDriverWarnings: false
    hardFailOnLoopback: false
    noCEOnEE: false
    dockerRegistryIP: 192.168.0.1
    additionalNoProxy: 129.168.0.2
    noDocker: false
  weave:
    version: latest
    encryptNetwork: true
    podCidrRange: /12
    podCIDR: 39.1.2.3
  contour:
    version: latest
  rook:
    version: latest
    storageClassName: default
    cephReplicaCount: 1
  openebs:
    version: latest
    namespace: openebs
    isLocalPVEnabled: true
    localPVStorageClassName: default
    isCstorEnabled: true
    cstorStorageClassName: cstor
  minio:
    version: latest
    namespace: minio
  registry:
    version: latest
    publishPort: 20
  prometheus:
    version: latest
  fluentd:
    version: latest
    fullEFKStack: false
  kotsadm:
    version: latest
    applicationSlug: sentry
    uiBindPort: 8800
    applicationNamespace: kots
    hostname: 1.1.1.1
  velero:
    version: latest
    namespace: velero
    disableCLI: false
    disableRestic: false
    localBucket: local
  ekco:
    version: latest
    nodeUnreachableTolerationDuration: 10m
    minReadyMasterNodeCount: 3
    minReadyWorkerNodeCount: 1
    shouldDisableRebootService: false
    rookShouldUseAllNodes: false
  kurl:
    HTTPProxy: 1.1.1.1
    airgap: false
    bypassFirewalldWarning: false
    hardFailOnFirewalld: false
    hostnameCheck: 2.2.2.2
    noProxy: false
    privateAddress: 10.38.1.1
    publicAddress: 101.38.1.1
    task: important
`;

const typeMetaStableV1Beta1 = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: stable
spec:
  kubernetes:
    version: 1.15.2
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0
  registry:
    version: 2.7.1
  prometheus:
    version: 0.33.0
`;

const stable = `
metadata:
  name: stable
spec:
  kubernetes:
    version: 1.15.2
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0
  registry:
    version: 2.7.1
  prometheus:
    version: 0.33.0
`;

const noName = `
spec:
  kubernetes:
    version: 1.15.2
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0
  registry:
    version: 2.7.1
  prometheus:
    version: 0.33.0
`;

const disordered = `
spec:
  contour:
    version: 0.14.0
  weave:
    version: 2.5.2
  prometheus:
    version: 0.33.0
  kubernetes:
    version: 1.15.2
  registry:
    version: 2.7.1
  rook:
    version: 1.0.4
`;

const k8s14 = `
spec:
  kubernetes:
    version: 1.14.5
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0
  registry:
    version: 2.7.1
  prometheus:
    version: 0.33.0
`;

const min = `
spec:
  kubernetes:
    version: 1.15.1
`;

const empty = "";

const kots = `
spec:
  kubernetes:
    version: latest
  kotsadm:
    version: 0.9.9
    applicationSlug: sentry-enterprise
`;

const kotsNoSlug = `
spec:
  kubernetes:
    version: latest
  kotsadm:
    version: 0.9.9
`;

const kotsNoVersion = `
spec:
  kubernetes:
    version: latest
  kotsadm:
    applicationSlug: sentry-enterprise
`;

const velero = `
spec:
  velero:
    version: latest
    namespace: not-velero
    installCLI: false
    useRestic: false
`;

const veleroMin = `
spec:
  velero:
    version: latest
`;

const veleroDefaults = `
spec:
  velero:
    version: latest
    namespace: velero
`;

const fluentd = `
spec:
  fluentd:
    version: latest
    fullEFKStack: true
`;

const fluentdMin = `
spec:
  fluentd:
    version: latest
`;

const ekco = `
spec:
  ekco:
    version: latest
    nodeUnreachableTolerationDuration: 10m
    minReadyMasterNodeCount: 3
    minReadyWorkerNodeCount: 1
    shouldDisableRebootService: false
    rookShouldUseAllNodes: false
`;

const ekcoMin = `
spec:
  ekco:
    version: latest
`;

const openebs = `
spec:
  openebs:
    version: latest
    isLocalPVEnabled: true
    localPVStorageClassName: default
    isCstorEnabled: true
    cstorStorageClassName: cstor
`;

describe("Installer", () => {
  describe("parse", () => {
    it("parses yaml with type meta and name", () => {
      const i = Installer.parse(typeMetaStableV1Beta1);
      expect(i).to.have.property("id", "stable");
      expect(i.spec.kubernetes).to.have.property("version", "1.15.2");
      expect(i.spec.weave).to.have.property("version", "2.5.2");
      expect(i.spec.rook).to.have.property("version", "1.0.4");
      expect(i.spec.contour).to.have.property("version", "0.14.0");
      expect(i.spec.registry).to.have.property("version", "2.7.1");
      expect(i.spec.prometheus).to.have.property("version", "0.33.0");
    });

    it("parses yaml with name and no type meta", () => {
      const i = Installer.parse(stable);
      expect(i).to.have.property("id", "stable");
      expect(i.spec.kubernetes).to.have.property("version", "1.15.2");
      expect(i.spec.weave).to.have.property("version", "2.5.2");
      expect(i.spec.rook).to.have.property("version", "1.0.4");
      expect(i.spec.contour).to.have.property("version", "0.14.0");
      expect(i.spec.registry).to.have.property("version", "2.7.1");
      expect(i.spec.prometheus).to.have.property("version", "0.33.0");
    });

    it("parses yaml with only a spec", () => {
      const i = Installer.parse(noName);
      expect(i).to.have.property("id", "");
      expect(i.spec.kubernetes).to.have.property("version", "1.15.2");
      expect(i.spec.weave).to.have.property("version", "2.5.2");
      expect(i.spec.rook).to.have.property("version", "1.0.4");
      expect(i.spec.contour).to.have.property("version", "0.14.0");
      expect(i.spec.registry).to.have.property("version", "2.7.1");
      expect(i.spec.prometheus).to.have.property("version", "0.33.0");
    });

    it("parses yaml spec in different order", () => {
      const i = Installer.parse(disordered);
      expect(i).to.have.property("id", "");
      expect(i.spec.kubernetes).to.have.property("version", "1.15.2");
      expect(i.spec.weave).to.have.property("version", "2.5.2");
      expect(i.spec.rook).to.have.property("version", "1.0.4");
      expect(i.spec.contour).to.have.property("version", "0.14.0");
      expect(i.spec.registry).to.have.property("version", "2.7.1");
      expect(i.spec.prometheus).to.have.property("version", "0.33.0");
    });

    it("parses yaml spec with empty versions", () => {
      const i = Installer.parse(min);
      expect(i).to.have.property("id", "");
      expect(i.spec.kubernetes).to.have.property("version", "1.15.1");
      expect(i.spec).not.to.have.property("weave");
      expect(i.spec).not.to.have.property("rook");
      expect(i.spec).not.to.have.property("contour");
      expect(i.spec).not.to.have.property("registry");
      expect(i.spec).not.to.have.property("kotsadm");
      expect(i.spec).not.to.have.property("docker");
      expect(i.spec).not.to.have.property("prometheus");
      expect(i.spec).not.to.have.property("velero");
      expect(i.spec).not.to.have.property("fluentd");
    });
  });

  describe("hash", () => {
    it("hashes same specs to the same string", () => {
      const a = Installer.parse(typeMetaStableV1Beta1).hash();
      const b = Installer.parse(stable).hash();
      const c = Installer.parse(noName).hash();
      const d = Installer.parse(disordered).hash();

      expect(a).to.equal(b);
      expect(a).to.equal(c);
      expect(a).to.equal(d);
    });

    it("hashes different specs to different strings", () => {
      const a = Installer.parse(typeMetaStableV1Beta1).hash();
      const b = Installer.parse(k8s14).hash();

      expect(a).not.to.equal(b);
    });

    it("hashes to a 7 character hex string", () => {
      const a = Installer.parse(typeMetaStableV1Beta1).hash();
      const b = Installer.parse(k8s14).hash();

      expect(a).to.match(/[0-9a-f]{7}/);
      expect(b).to.match(/[0-9a-f]{7}/);
    });

    it("hashes old versions to equivalent migrated version", () => {
      const parsedV1Beta1 = Installer.parse(typeMetaStableV1Beta1);
    });
  });

  describe("toYAML", () => {
    describe("v1beta1", () => {
      it("leaves missing names empty", () => {
        const parsed = Installer.parse(noName);
        const yaml = parsed.toYAML();

        expect(yaml).to.equal(`apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: ''
spec:
  kubernetes:
    version: 1.15.2
  weave:
    version: 2.5.2
  rook:
    version: 1.0.4
  contour:
    version: 0.14.0
  registry:
    version: 2.7.1
  prometheus:
    version: 0.33.0
`);
      });

      it("renders empty yaml", () => {
        const parsed = Installer.parse(empty);
        const yaml = parsed.toYAML();

        expect(yaml).to.equal(`apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: ''
spec:
  kubernetes:
    version: ''
`);
      });
    });
  });

  describe("Installer.isSHA", () => {
    [
      { id: "d3a9234", answer: true },
      { id: "6898644", answer: true },
      { id: "0000000", answer: true},
      { id: "abcdefa", answer: true},
      { id: "68986440", answer: false },
      { id: "d3a923", answer: false },
      { id: "latest", answer: false },
      { id: "f3a9g34", answer: false },
      { id: "replicated-beta", answer: false },
      { id: "replicated d3a9234", answer: false },
    ].forEach((test) => {
      it(`${test.id} => ${test.answer}`, () => {
        const output = Installer.isSHA(test.id);

        expect(Installer.isSHA(test.id)).to.equal(test.answer);
      });
    });
  });

  describe("Installer.isValidSlug", () => {
    [
      { slug: "ok", answer: true },
      { slug: "", answer: false},
      { slug: " ", answer: false},
      { slug: "big-bank-beta", answer: true},
      { slug: _.range(0, 255).map((x) => "a").join(""), answer: true },
      { slug: _.range(0, 256).map((x) => "a").join(""), answer: false },
    ].forEach((test) => {
      it(`"${test.slug}" => ${test.answer}`, () => {
        const output = Installer.isValidSlug(test.slug);

        expect(Installer.isValidSlug(test.slug)).to.equal(test.answer);
      });
    });
  });

  describe("Installer.isValidCidrRange", () => {
    [
      { cidrRange: "/12", answer: true },
      { cidrRange: "12", answer: true},
      { cidrRange: " ", answer: false},
      { cidrRange: "abc", answer: false},
    ].forEach((test) => {
      it(`"${test.cidrRange}" => ${test.answer}`, () => {
        const output = Installer.isValidCidrRange(test.cidrRange);

        expect(Installer.isValidCidrRange(test.cidrRange)).to.equal(test.answer);
      });
    });
  });

  describe("validate", () => {
    describe("valid", () => {
      it("=> void", () => {
        [
          typeMetaStableV1Beta1,
        ].forEach(async (yaml) => {
          const out = Installer.parse(yaml).validate();

          expect(out).to.equal(undefined);
        });
      });

      describe("application slug exists", () => {
        it("=> void", () => {
          const out = Installer.parse(kots).validate();

          expect(out).to.equal(undefined);
        });
      });

      describe("every option", () => {
        it("=> void", () => {
          const out = Installer.parse(everyOption).validate();

          expect(out).to.equal(undefined);
        });
      });
    });

    describe("invalid Kubernetes versions", () => {
      it("=> ErrorResponse", () => {
        const noK8s = `
spec:
  kubernetes:
    version: ""
`;
        const noK8sOut = Installer.parse(noK8s).validate();
        expect(noK8sOut).to.deep.equal({ error: { message: "Kubernetes version is required" } });

        const badK8s = `
spec:
  kubernetes:
    version: "0.15.3"
`;
        const badK8sOut = Installer.parse(badK8s).validate();
        expect(badK8sOut).to.deep.equal({ error: { message: "Kubernetes version 0.15.3 is not supported" } });
      });
    });

    describe("invalid Prometheus version", () => {
      it("=> ErrorResponse", () => {
        const yaml = `
spec:
  kubernetes:
    version: latest
  prometheus:
    version: 0.32.0
`;
        const out = Installer.parse(yaml).validate();

        expect(out).to.deep.equal({ error: { message: `Prometheus version "0.32.0" is not supported` } });
      });
    });

    describe("kots version missing", () => {
      it("=> ErrorResponse", () => {
        const out = Installer.parse(kotsNoVersion).validate();

        expect(out).to.deep.equal({ error: { message: "spec.kotsadm should have required property 'version'" }});
      });
    });

    describe("docker version is a boolean", () => {
      const yaml = `
spec:
  kubernetes:
    version: latest
  docker:
    version: true`;
      const i = Installer.parse(yaml);
      const out = i.validate();

      expect(out).to.deep.equal({ error: { message: "spec.docker.version should be string" } });
    });

    describe("invalid podCidrRange", () => {
      const yaml = `
spec:
  kubernetes:
    version: latest
  weave:
    version: latest
    podCidrRange: abc`;
      const i = Installer.parse(yaml);
      const out = i.validate();

      expect(out).to.deep.equal({ error: { message: "Weave podCidrRange \"abc\" is invalid" } });
    });

    describe("invalid serviceCidrRange", () => {
      const yaml = `
spec:
  kubernetes:
    version: latest
    serviceCidrRange: abc`;
      const i = Installer.parse(yaml);
      const out = i.validate();

      expect(out).to.deep.equal({ error: { message: "Kubernetes serviceCidrRange \"abc\" is invalid" } });
    });

    describe("extra options", () => {
      it("=> ErrorResponse", () => {
        const yaml = `
spec:
  kubernetes:
    version: latest
    seLinux: true`;
        const i = Installer.parse(yaml);
        const out = i.validate();

        expect(out).to.deep.equal({ error: { message: "spec.kubernetes should NOT have additional properties" } });
      });
    });
  });

  describe("flags", () => {
    describe("every option", () => {
      it(`=> service-cidr-range=/12 ...`, () => {
        const i = Installer.parse(everyOption);

          expect(i.flags()).to.equal("service-cidr-range=/12 service-cidr=100.1.1.1/12 ha=0 kuberenetes-master-address=192.168.1.1 load-balancer-address=10.128.10.1 bootstrap-token=token bootstrap-token-ttl=10min kubeadm-token-ca-hash=hash control-plane=0 cert-key=key bypass-storagedriver-warnings=0 hard-fail-on-loopback=0 no-ce-on-ee=0 docker-registry-ip=192.168.0.1 additional-no-proxy=129.168.0.2 no-docker=0 pod-cidr=39.1.2.3 pod-cidr-range=/12 disable-weave-encryption=0 storage-class-name=default ceph-replica-count=1 openebs-namespace=openebs openebs-localpv-enabled=1 openebs-localpv-storage-class-name=default openebs-cstor-enabled=1 openebs-cstor-storage-class-name=cstor minio-namespace=minio registry-publish-port=20 fluentd-full-efk-stack=0 kotsadm-application-slug=sentry kotsadm-ui-bind-port=8800 kotsadm-hostname=1.1.1.1 kotsadm-application-namespaces=kots velero-namespace=velero velero-local-bucket=local velero-disable-cli=0 velero-disable-restic=0 ekco-node-unreachable-toleration-duration=10m ekco-min-ready-master-node-count=3 ekco-min-ready-worker-node-count=1 ekco-should-disable-reboot-service=0 ekco-rook-should-use-all-nodes=0 http-proxy=1.1.1.1 airgap=0 bypass-firewalld-warning=0 hard-fail-on-firewalld=0 hostname-check=2.2.2.2 no-proxy=0 private-address=10.38.1.1 public-address=101.38.1.1 task=important");
      });
    });
  });

  describe("velero", () => {
    it("should parse", () => {
      const i = Installer.parse(velero);

      expect(i.spec.velero).to.deep.equal({
        version: "latest",
        namespace: "not-velero",
        installCLI: false,
        useRestic: false,
      });
    });
  });

  describe("velero minimum spec flags", () => {
    it("should not generate any flags", () => {
      const i = Installer.parse(veleroMin);

      expect(i.flags()).to.equal(``);
    });
  });

  describe("velero defaults", () => {
    it("should generate only the velero-namespace flag", () => {
      const i = Installer.parse(veleroDefaults);

      expect(i.flags()).to.equal(`velero-namespace=velero`);
    });
  });

  describe("fluentd", () => {
    it("should parse", () => {
      const i = Installer.parse(fluentd);

      expect(i.spec.fluentd).to.deep.equal({
        version: "latest",
        fullEFKStack: true,
      });
    });
  });

  describe("fluentd minimum spec flags", () => {
    it("should not generate any flags", () => {
      const i = Installer.parse(fluentdMin);

      expect(i.flags()).to.equal(``);
    });
  });

  describe("openebs", () => {
    it("should parse", () => {
      const i = Installer.parse(everyOption);

      expect(i.spec.openebs.namespace).to.equal("openebs");
    });
  });

  describe("ekco", () => {
    it("should parse", () => {
      const i = Installer.parse(ekco);

      expect(i.spec.ekco).to.deep.equal({
        version: "latest",
        nodeUnreachableTolerationDuration: "10m",
        minReadyMasterNodeCount: 3,
        minReadyWorkerNodeCount: 1,
        shouldDisableRebootService: false,
        rookShouldUseAllNodes: false,
      });
        expect(i.flags()).to.equal("ekco-node-unreachable-toleration-duration=10m ekco-min-ready-master-node-count=3 ekco-min-ready-worker-node-count=1 ekco-should-disable-reboot-service=0 ekco-rook-should-use-all-nodes=0")
    });
  });

  describe("ekco minimum spec flags", () => {
    it("should not generate any flags", () => {
      const i = Installer.parse(ekcoMin);

      expect(i.flags()).to.equal(``);
    });
  });

  describe("openebs", () => {
    it("should parse", () => {
      const i = Installer.parse(openebs);

      expect(i.spec.openebs).to.deep.equal({
        version: "latest",
        isLocalPVEnabled: true,
        localPVStorageClassName: "default",
        isCstorEnabled: true,
        cstorStorageClassName: "cstor",
      });
    });
  });
});
