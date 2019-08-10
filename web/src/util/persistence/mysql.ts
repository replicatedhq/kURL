import * as mysql from "promise-mysql";
import { gauge } from "monkit";

import param from "../params";
import { logger } from "../../logger";

interface MySQLPoolInternal {
  _acquiringConnections: mysql.Connection[];
  _allConnections: mysql.Connection[];
  _freeConnections: mysql.Connection[];
  _connectionQueue: mysql.Connection[];
}

interface MySQLPoolWithInternals extends mysql.Pool {
  pool: MySQLPoolInternal;
}

interface MySQLPoolMetrics {
  waitingCount: number;
  totalCount: number;
  idleCount: number;
  activeCount: number;
}

const getMysqlPoolMetrics = (pool: mysql.Pool): MySQLPoolMetrics => {
  const { pool: internalPool } = pool as MySQLPoolWithInternals;

  return {
    waitingCount: internalPool._acquiringConnections.length,
    totalCount: internalPool._allConnections.length,
    idleCount: internalPool._freeConnections.length,
    activeCount: internalPool._allConnections.length - internalPool._freeConnections.length,
  };
};

export async function updatePoolGauges() {
  const pool = await getMysqlPool();

  const {
    waitingCount,
    totalCount,
    idleCount,
    activeCount,
  } = getMysqlPoolMetrics(pool);
  gauge("id.MySQLPool.waiting.count").set(waitingCount);
  gauge("id.MySQLPool.total.count").set(totalCount);
  gauge("id.MySQLPool.idle.count").set(idleCount);
  gauge("id.MySQLPool.active.count").set(activeCount);
}

let mysqlPool: mysql.Pool;
export async function initMysqlPool(): Promise<void> {
  const host = await param("MYSQL_HOST", "/mysql/host");
  const port = parseInt(await param("MYSQL_PORT", "/mysql/port") || "3306");
  const user = await param("MYSQL_USER", "/mysql/user");
  const database = await param("MYSQL_DATABASE", "/mysql/database");
  const connectionLimit = Number(await param("MYSQL_POOL_SIZE", "/mysql/pool_size")) || 10;
  const password = await param("MYSQL_PASSWORD", "/mysql/password", true);

  logger.info(`Connecting to mysql with connection string: server=${host}port=${port};;uid=${user};pwd=*******;database=${database}`);
  mysqlPool = await mysql.createPool({
    connectionLimit,
    host,
    port,
    user,
    password,
    database,
  });
}

export default function getMysqlPool(): mysql.Pool {
  return mysqlPool;
}
