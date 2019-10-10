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

  public async putInstaller(jwt: string, name: string, yaml: string): Promise<string> {
    const resp = await request
      .put(`${this.kurlURL}/installer/${name}`)
      .set("Content-Type", "text/yaml")
      .set("Authorization", `Bearer ${jwt}`)
      .send(yaml);

    return resp.text;
  }

  public async getInstallScript(installerID: string): Promise<string> {
    const resp = await request
      .get(`${this.kurlURL}/${installerID}`)
      .send();

    return resp.text;
  }

  public async getJoinScript(installerID: string): Promise<string> {
    const resp = await request
      .get(`${this.kurlURL}/${installerID}/join.sh`)
      .send();

    return resp.text;
  }

  public async getInstallerYAML(installerID: string, resolve?: boolean): Promise<string> {
    let url = `${this.kurlURL}/installer/${installerID}`;

    if (resolve) {
      url += "?resolve=true";
    }

    const resp = await request
      .get(url)
      .set("Accept", "text/yaml")
      .send();

    return resp.text;
  }

  public async getInstallerJSON(installerID: string, resolve?: boolean): Promise<any> {
    let url = `${this.kurlURL}/installer/${installerID}`;

    if (resolve) {
      url += "?resolve=true";
    }

    const resp = await request
      .get(url)
      .set("Accept", "application/json")
      .send();

    return resp.body;
  }

  public async getVersions(): Promise<any> {
    let url = `${this.kurlURL}/installer`;

    const resp = await request
      .get(url)
      .send();

    return resp.body;
  }
}
