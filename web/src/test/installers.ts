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

const empty = "";

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
});
