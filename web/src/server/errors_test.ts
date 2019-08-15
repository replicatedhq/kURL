import {describe, it} from "mocha";
import {expect} from "chai";
import { HTTPError, ServerError, Unauthorized } from "./errors";
import {SignupAPI} from "../controllers/SignupAPI";

describe("Errors", () => {
  describe("unauthorized", () => {
    const err = new Unauthorized();
    it("has a code of 401", () => {
      expect(err.status).to.equal(401);
    });
  });

  describe("ServerError", () => {
    const err = new ServerError();
    it("has a code of 500", () => {
      expect(err.status).to.equal(500);
    });
  });

  describe("HTTPError.requireMatch()", () => {
    it("allows valid emails", () => {
      HTTPError.requireMatch("a@b.c", SignupAPI.EMAIL_REGEXP, "email");
    });
    it("throws on invalid emails", () => {
      expect(() => {
        HTTPError.requireMatch("a@b@c.d", SignupAPI.EMAIL_REGEXP, "email");
      }).to.throw("Missing or invalid parameters: email");
    });
    it("allows valid company name", () => {
      HTTPError.requireMatch("hi ho", SignupAPI.LENGTH_REGEXP, "company");
    });
    it("throws on invalid company name", () => {
      expect(() => {
        HTTPError.requireMatch(" ", SignupAPI.LENGTH_REGEXP, "company");
      }).to.throw("Missing or invalid parameters: company");
    });
  });

});
