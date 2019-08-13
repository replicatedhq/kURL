import * as jwt from "jsonwebtoken";
import * as _ from "lodash";
import param from "../params";

// returns team ID
export default async function decode(auth: string): Promise<string> {
  if (!_.startsWith(auth, "Bearer")) {
    return "";
  }
  const claims = jwt.verify(auth.split(" ").pop(), await(param("JWT_SIGNING_KEY", "/id/jwt_signing_key", true)));

  return claims.team_id;
}
