import {describe, it} from "mocha";
import {expect} from "chai";
import { Installer } from "../../installers";
import * as _ from "lodash";

describe("Installer (K3S)", () => {

    describe("invalid K3S versions", () => {
      it("=> ErrorResponse", async () => {
        const badK3S = `
spec:
  k3s:
    version: "0.15.3"
`;
        const badK8sOut = await Installer.parse(badK3S).validate();
        expect(badK8sOut).to.deep.equal({ error: { message: "K3S version 0.15.3 is not supported" } });
      });
    });

    describe("valid K3S versions", () => {
      it("=> void", async () => {
        const goodK3S = `
spec:
  k3s:
    version: "v1.19.7+k3s1"
`;
        const out = await Installer.parse(goodK3S).validate();

        expect(out).to.equal(undefined);
      });
    });

    describe("both Kubernetes and K3S", () => {
      it("=> ErrorResponse", async () => {
        const bad = `
spec:
  kubernetes:
    version: "1.19.3"
  k3s:
    version: "v1.19.7+k3s1"
`;
        const badK8sOut = await Installer.parse(bad).validate();
        expect(badK8sOut).to.deep.equal({ error: { message: "This spec contains both kubeadm and k3s, please specifiy only one Kubernetes distribution" } });
      });
    });

});
