import {describe, it} from "mocha";
import {expect} from "chai";
import { Installer } from "../../installers";
import * as _ from "lodash";

describe("Installer (RKE2)", () => {

  describe("invalid RKE2 versions", () => {
    it("=> ErrorResponse", async () => {
      const badRKE2 = `
spec:
  rke2:
    version: "0.15.3"
`;
      const badK8sOut = await Installer.parse(badRKE2).validate();
      expect(badK8sOut).to.deep.equal({ error: { message: "RKE2 version 0.15.3 is not supported" } });
    });
  });

  describe("valid RKE2 versions", () => {
    it("=> void", async () => {
      const goodRKE2 = `
spec:
  rke2:
    version: "v1.19.7+rke2r1"
`;
      const out = await Installer.parse(goodRKE2).validate();

      expect(out).to.equal(undefined);
    });
  });

  describe("both Kubernetes and RKE2", () => {
    it("=> ErrorResponse", async () => {
      const bad = `
spec:
  kubernetes:
    version: "1.19.3"
  rke2:
    version: "v1.19.7+rke2r1"
`;
      const badK8sOut = await Installer.parse(bad).validate();
      expect(badK8sOut).to.deep.equal({ error: { message: "This spec contains both kubeadm and rke2, please specifiy only one Kubernetes distribution" } });
    });
  });

});
