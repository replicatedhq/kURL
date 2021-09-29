import * as jwt from "jsonwebtoken";
import * as _ from "lodash";
import * as crypto from 'crypto';
import getMysqlPool from "../persistence/mysql";
import param from "../params";

// returns team ID
export default async function decode(auth: string): Promise<string> {
  if (_.startsWith(auth, "Bearer")) {
    const claims = jwt.verify(auth.split(" ").pop(), await(param("JWT_SIGNING_KEY", "/id/jwt_signing_key", true)));
    return claims.team_id;
  } else {
    const q = `select teamid, name, access_token, is_system_token, last_active, read_only from vendor_team_access_token where access_token = ?`;
    const v = [auth];
    const pool = getMysqlPool();
    let result = await pool.query(q, v);

    // check for a hashed token in case it's a user or service account
    if (result.length === 0) {
      const encoded = crypto.createHash('sha256').update(auth).digest('base64');
      result = await pool.query(q, encoded);
    }

    if (result.length === 0 || result[0].read_only) {
      return "";
    }

    return result[0].teamid;
  }
}
