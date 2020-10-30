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

const collectd = `
apiVersion: kurl.sh/v1beta1
kind: Installer
metadata:
  name: collectd
spec:
  kubernetes:
    version: 1.17.7
  docker:
    version: 19.03.10
  weave:
    version: 2.7.0
  collectd:
    version: 0.0.1
`;

describe("script with collectd config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(collectd);

		expect(uri).to.match(/321d006/);

		const script = await client.getInstallScript("321d006");

		expect(script).to.match(new RegExp(`collectd:`));
		expect(script).to.match(new RegExp(`version: 0.0.1`));
    console.log(script);
	});
});
