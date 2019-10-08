import {describe, it} from "mocha";
import {expect} from "chai";
import { Installer } from "../installers";
import * as _ from "lodash";

const typeMetaStable = `
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
`;

const disordered = `
spec:
  contour:
    version: 0.14.0
  weave:
    version: 2.5.2
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
    version: 0.9.8
    applicationSlug: sentry-enterprise
`;

const kotsNoSlug = `
spec:
  kubernetes:
    version: latest
  kotsadm:
    version: 0.9.8
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
      const i = Installer.parse(typeMetaStable);
      expect(i).to.have.property("id", "stable");
      expect(i.kubernetes).to.have.property("version", "1.15.2");
      expect(i.weave).to.have.property("version", "2.5.2");
      expect(i.rook).to.have.property("version", "1.0.4");
      expect(i.contour).to.have.property("version", "0.14.0");
      expect(i.registry).to.have.property("version", "2.7.1");
    });

    it("parses yaml with name and no type meta", () => {
      const i = Installer.parse(stable);
      expect(i).to.have.property("id", "stable");
      expect(i.kubernetes).to.have.property("version", "1.15.2");
      expect(i.weave).to.have.property("version", "2.5.2");
      expect(i.rook).to.have.property("version", "1.0.4");
      expect(i.contour).to.have.property("version", "0.14.0");
      expect(i.registry).to.have.property("version", "2.7.1");
    });

    it("parses yaml with only a spec", () => {
      const i = Installer.parse(noName);
      expect(i).to.have.property("id", "");
      expect(i.kubernetes).to.have.property("version", "1.15.2");
      expect(i.weave).to.have.property("version", "2.5.2");
      expect(i.rook).to.have.property("version", "1.0.4");
      expect(i.contour).to.have.property("version", "0.14.0");
      expect(i.registry).to.have.property("version", "2.7.1");
    });

    it("parses yaml spec in different order", () => {
      const i = Installer.parse(disordered);
      expect(i).to.have.property("id", "");
      expect(i.kubernetes).to.have.property("version", "1.15.2");
      expect(i.weave).to.have.property("version", "2.5.2");
      expect(i.rook).to.have.property("version", "1.0.4");
      expect(i.contour).to.have.property("version", "0.14.0");
      expect(i.registry).to.have.property("version", "2.7.1");
    });

    it("parses yaml spec with empty versions", () => {
      const i = Installer.parse(min);
      expect(i).to.have.property("id", "");
      expect(i.kubernetes).to.have.property("version", "1.15.1");
      expect(i.weave).to.have.property("version", "");
      expect(i.rook).to.have.property("version", "");
      expect(i.contour).to.have.property("version", "");
      expect(i.registry).to.have.property("version", "");
    });
  });

  describe("hash", () => {
    it("hashes same specs to the same string", () => {
      const a = Installer.parse(typeMetaStable).hash();
      const b = Installer.parse(stable).hash();
      const c = Installer.parse(noName).hash();
      const d = Installer.parse(disordered).hash();

      expect(a).to.equal(b);
      expect(a).to.equal(c);
      expect(a).to.equal(d);
    });

    it("hashes different specs to different strings", () => {
      const a = Installer.parse(typeMetaStable).hash();
      const b = Installer.parse(k8s14).hash();

      expect(a).not.to.equal(b);
    });

    it("hashes to a 7 character hex string", () => {
      const a = Installer.parse(typeMetaStable).hash();
      const b = Installer.parse(k8s14).hash();

      expect(a).to.match(/[0-9a-f]{7}/);
      expect(b).to.match(/[0-9a-f]{7}/);
    });
  });

  describe("toYAML", () => {
    it("returns standardized yaml", () => {
      const a = Installer.parse(typeMetaStable).toYAML();
      const b = Installer.parse(stable).toYAML();
      const c = Installer.parse(noName).toYAML();
      const d = Installer.parse(disordered).toYAML();
      const e = Installer.parse(empty).toYAML();

      expect(a).to.equal(`apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: "stable"
spec:
  kubernetes:
    version: "1.15.2"
  weave:
    version: "2.5.2"
  rook:
    version: "1.0.4"
  contour:
    version: "0.14.0"
  registry:
    version: "2.7.1"
  kotsadm:
    version: ""
    applicationSlug: ""
`);
      expect(b).to.equal(a);

      expect(c).to.equal(`apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: "1.15.2"
  weave:
    version: "2.5.2"
  rook:
    version: "1.0.4"
  contour:
    version: "0.14.0"
  registry:
    version: "2.7.1"
  kotsadm:
    version: ""
    applicationSlug: ""
`);
      expect(d).to.equal(c);

      expect(e).to.equal(`apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: ""
spec:
  kubernetes:
    version: ""
  weave:
    version: ""
  rook:
    version: ""
  contour:
    version: ""
  registry:
    version: ""
  kotsadm:
    version: ""
    applicationSlug: ""
`);
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

  describe("isEqual", () => {
    describe("equal", () => {
      it("=> true", () => {
        const a = Installer.parse(typeMetaStable);
        const b = Installer.parse(noName);
        const c = Installer.parse(disordered);

        expect(a.specIsEqual(a)).to.equal(true);
        expect(a.specIsEqual(b)).to.equal(true);
        expect(a.specIsEqual(c)).to.equal(true);
        expect(b.specIsEqual(a)).to.equal(true);
        expect(b.specIsEqual(b)).to.equal(true);
        expect(b.specIsEqual(c)).to.equal(true);
        expect(c.specIsEqual(a)).to.equal(true);
        expect(c.specIsEqual(b)).to.equal(true);
        expect(c.specIsEqual(c)).to.equal(true);
      });
    });

    describe("inequal", () => {
      it("=> false", () => {
        const a = Installer.parse(typeMetaStable);
        const b = Installer.parse(k8s14);

        expect(a.specIsEqual(b)).to.equal(false);
        expect(b.specIsEqual(a)).to.equal(false);
      });
    });
  });

  describe("validate", () => {
    describe("valid", () => {
      it("=> void", async () => {
        [
          typeMetaStable,
        ].forEach(async (yaml) => {
          const out = await Installer.parse(yaml).validate();
          
          expect(out).to.be.undefined;
        });
      });

      describe("application slug exists", () => {
        it("=> void", async () => {
          const out = await Installer.parse(kots).validate();

          expect(out).to.be.undefined;
        });
      });

      describe("kots application slug missing", () => {
        it("=> ErrorResponse", async () => {
          const out = await Installer.parse(kotsNoSlug).validate();

          expect(out).to.be.undefined;
        });
      });
    });

    describe("invalid", () => {
      it("=> ErrorResponse", async () => {
        const noK8s = `
spec:
  kubernetes:
    version: ""
`
        const noK8sOut = await Installer.parse(noK8s).validate();
        expect(noK8sOut).to.deep.equal({ error: { message: "Kubernetes version is required" } });

        const badK8s = `
spec:
  kubernetes:
    version: "0.15.3"
`
        const badK8sOut = await Installer.parse(badK8s).validate();
        expect(badK8sOut).to.deep.equal({ error: { message: "Kubernetes version 0.15.3 is not supported" } });
      });
    });

    describe("kots version missing", () => {
      it("=> ErrorResponse", async () => {
        const out = await Installer.parse(kotsNoVersion).validate();

        expect(out).to.deep.equal({ error: { message: "Kotsadm version is required when application slug is set" }});
      });
    });

    describe("kots application does not exist", () => {
      it("=> ErrorResponse", async () => {
        const parsed = Installer.parse(kots);

        parsed.kotsadm.applicationSlug = "this-app-does-not-exist";

        const out = await parsed.validate();

        expect(out).to.deep.equal({ error: { message: "Kotsadm application 'this-app-does-not-exist' not found" }});
      });
    });
  });
});
