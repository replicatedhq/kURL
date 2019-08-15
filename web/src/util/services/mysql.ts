import {Service} from "ts-express-decorators";
import * as mysql from "promise-mysql";
import getMysqlPool from "../persistence/mysql";

@Service()
export class MysqlWrapper {

  constructor() {
    this.pool = getMysqlPool();
  }

  public pool: mysql.Pool;

}
