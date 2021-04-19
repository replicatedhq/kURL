import * as request from "superagent";

export class KurlClient {

  constructor(
    private readonly kurlURL: string,
  ) {}

  public async postInstaller(yaml: string): Promise<string> {
    try {
      const resp = await request
        .post(`${this.kurlURL}/installer`)
        .set("Content-Type", "text/yaml")
        .send(yaml);

      return resp.text;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async putInstaller(token: string, name: string, yaml: string): Promise<string> {
    const auth = `Bearer ${token}` || token;

    try {
      const resp = await request
        .put(`${this.kurlURL}/installer/${name}`)
        .set("Content-Type", "text/yaml")
        .set("Authorization", auth)
        .send(yaml);

      return resp.text;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async getInstallScript(installerID: string): Promise<string> {
    try {
      const resp = await request
        .get(`${this.kurlURL}/${installerID}`)
        .send();

      return resp.text;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async getJoinScript(installerID: string): Promise<string> {
    try {
      const resp = await request
        .get(`${this.kurlURL}/${installerID}/join.sh`)
        .send();

      return resp.text;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async getInstallerYAML(installerID: string, resolve?: boolean): Promise<string> {
    let url = `${this.kurlURL}/installer/${installerID}`;

    if (resolve) {
      url += "?resolve=true";
    }

    try {
      const resp = await request
        .get(url)
        .set("Accept", "text/yaml")
        .send();

      return resp.text;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async getInstallerJSON(installerID: string, resolve?: boolean): Promise<any> {
    let url = `${this.kurlURL}/installer/${installerID}`;

    if (resolve) {
      url += "?resolve=true";
    }

    try {
      const resp = await request
        .get(url)
        .set("Accept", "application/json")
        .send();

      return resp.body;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async getVersions(): Promise<any> {
    const url = `${this.kurlURL}/installer`;

    try {
      const resp = await request
        .get(url)
        .send();

      return resp.body;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }

  public async validateInstaller(yaml: string): Promise<string> {
    try {
      const resp = await request
        .post(`${this.kurlURL}/installer/validate`)
        .set("Content-Type", "text/yaml")
        .send(yaml);

      return resp.text;
    } catch (e) {
      if (e.response && e.response.body && e.response.body.error && e.response.body.error.message) {
        throw new Error(e.response.body.error.message);
      }
      throw e;
    }
  }
}
