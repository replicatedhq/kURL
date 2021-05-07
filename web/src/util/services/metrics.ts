import { Service } from "ts-express-decorators";
import * as mysql from "promise-mysql";
import { MysqlWrapper } from "./mysql";
import * as uuid from "uuid";

export interface GetInstallScriptEvent {
  id?: string;
  installerID: string;
  timestamp: Date;
  isAirgap: boolean;
  clientIP?: string;
  userAgent?: string;
}

@Service()
export class MetricsStore {
  private readonly pool: mysql.Pool;

  constructor({ pool }: MysqlWrapper) {
    this.pool = pool;
  }

  public async saveSaasScriptEvent(e: GetInstallScriptEvent): Promise<void> {
    const q = `INSERT INTO kurl_saas_script_metrics (
      id,
      installer_id,
      timestamp,
      is_airgap,
      client_ip,
      user_agent
    ) VALUES (
      ?,
      ?,
      ?,
      ?,
      ?,
      ?
    )`;
    const v = [
      uuid.v4(),
      e.installerID,
      e.timestamp,
      e.isAirgap,
      e.clientIP,
      e.userAgent,
    ];

    await this.pool.query(q, v);
  }
}
