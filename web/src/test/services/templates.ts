import {describe, it} from "mocha";
import {expect} from "chai";
import { bashStringEscape } from "../../util/services/templates";
import * as _ from "lodash";


describe("Escape Bash Special Characters", () => {

  it("escapes select characters", () => {
    const valid= String.raw`
daemonConfig: |
  {
      "double-quotes": ["\backslash", {"exclaimation": "!"}],
  }
`
    const out = bashStringEscape(valid);
    expect(out).to.contain(String.raw`\"double-quotes\": [\"\\backslash\", {\"exclaimation\": \"\!\"}],`);
  });

  // js-yaml will add single quotes to numeric objects to make valid yaml
  it("does not escape single quotes", () => {
    const singleQuotes= String.raw`metadata: '12345678'`
    const out = bashStringEscape(singleQuotes);
    expect(out).to.equal(singleQuotes);
  });

});
