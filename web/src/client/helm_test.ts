import * as path from "path";

import {describe, it} from "mocha";
import {expect} from "chai";
import { KurlClient } from ".";
import * as _ from "lodash";

const kurlURL = process.env.KURL_URL || "http://localhost:30092";
const client = new KurlClient(kurlURL);

const helm = `
spec:
  kubernetes:
    version: latest
  helm:
    helmfileSpec: |
      repositories:
      - name: nginx-stable
        url: https://helm.nginx.com/stable
      releases:
      - name: test-nginx-ingress
        chart: nginx-stable/nginx-ingress
        values:
        - controller:
            service:
              type: NodePort
              httpPort:
                nodePort: 30080
              httpsPort:
                nodePort: 30443
    additionalImages:
    - postgres
`;

describe("script with Helm + Helmfile config", () => {
	it("200", async () => {
		const uri = await client.postInstaller(helm);

		expect(uri).to.match(/4077ac3/);

		const script = await client.getInstallScript("4077ac3");

		expect(script).to.match(new RegExp(`helmfileSpec:`));
		expect(script).to.match(new RegExp(`          nodePort: 30080`));
	});
});
