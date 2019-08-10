import * as request from "superagent";

export class KurlClient {

  constructor(
    private readonly kurlURL: string,
  ) {}

  public async postInstaller(yaml: string): Promise<string> {
    const resp = await request
      .post(`${this.kurlURL}/installer`)   
      .set("Content-Type", "text/yaml")
      .send(yaml);

    return resp.text;
  }
}
