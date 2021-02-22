import {describe, it} from "mocha";
import {expect} from "chai";
import { bashStringEscape } from "../../util/services/templates";
import * as _ from "lodash";

const testConf= String.raw`
daemonConfig: |
  {
      "double-quotes": ["\backslash"],
      'singlequotes': [ {'exclaimation':'!'} ]
  }
`

describe("Escape Bash Special Characters", () => {

  it("escapes select characters", () => {
    const out = bashStringEscape(testConf);
    expect(out).to.contain(String.raw`\"double-quotes\": [\"\\backslash\"],`);
    expect(out).to.contain(String.raw`\'singlequotes\': [ {\'exclaimation\':\'\!\'} ]`);
  });

});
