import {describe, it} from "mocha";
import {expect} from "chai";
import { Installer } from "../installers";
import * as _ from "lodash";

const everyOption = `apiVersion: kurl.sh/v1beta1
spec:
  kubernetes:
    version: latest
    serviceCIDR: 10.96.0.0/12
  docker:
    version: latest
    bypassStorageDriverWarnings: false
    hardFailOnLoopback: false
    noCEOnEE: false
  weave:
    version: latest
    encryptNetwork: true
    IPAllocRange: 10.32.0.0/12
  contour:
    version: latest
  rook:
    version: latest
    storageClass: default
    cephPoolReplicas: 1
  registry:
    version: latest
  prometheus:
    version: latest
  kotsadm:
    version: latest
    applicationSlug: sentry
    uiBindPort: 8800
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

        expect(yaml).to.equal(`apiVersion: kurl.sh/v1beta1
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

        expect(yaml).to.equal(`apiVersion: kurl.sh/v1beta1
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
      { slug: _.range(0,255).map((x) => "a").join(""), answer: true },
      { slug: _.range(0,256).map((x) => "a").join(""), answer: false },
    ].forEach((test) => {
      it(`"${test.slug}" => ${test.answer}`, () => {
        const output = Installer.isValidSlug(test.slug);

        expect(Installer.isValidSlug(test.slug)).to.equal(test.answer);
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
          
          expect(out).to.be.undefined;
        });
      });

      describe("application slug exists", () => {
        it("=> void", () => {
          const out = Installer.parse(kots).validate();

          expect(out).to.be.undefined;
        });
      });

      describe("every option", () => {
        it("=> void", () => {
          const out = Installer.parse(everyOption).validate();

          expect(out).to.be.undefined;
        });
      });
    });

    describe("invalid Kubernetes versions", () => {
      it("=> ErrorResponse", () => {
        const noK8s = `
spec:
  kubernetes:
    version: ""
`
        const noK8sOut = Installer.parse(noK8s).validate();
        expect(noK8sOut).to.deep.equal({ error: { message: "Kubernetes version is required" } });

        const badK8s = `
spec:
  kubernetes:
    version: "0.15.3"
`
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
      it(`=> no-ce-on-ee=1`, () => {
        const i = Installer.parse(everyOption);

        expect(i.flags()).to.equal(`service-cidr=10.96.0.0/12 bypass-storagedriver-warnings=0 hard-fail-on-loopback=0 no-ce-on-ee=0 ip-alloc-range=10.32.0.0/12 encrypt-network=1 storage-class=default ceph-pool-replicas=1 kotsadm-ui-bind-port=8800`);
      });
    });
  });
});
