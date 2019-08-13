import * as AWS from "aws-sdk";
import * as monkit from "monkit";
import { logger } from "../../logger";

let ssmClient: AWS.SSM;

export default async function(envName: string, ssmName: string, encrypted = false): Promise<string> {
  if (process.env["USE_EC2_PARAMETERS"]) {
    if (!ssmClient) {
      ssmClient = new AWS.SSM({
        apiVersion: "2014-11-06",
      });
    }
    const params: AWS.SSM.GetParametersRequest = {
      Names: [
        ssmName,
      ],
      WithDecryption: encrypted,
    };

    return await monkit.instrument("ssmClient.getParameters", async () => {
      const result = await ssmClient.getParameters(params).promise();
      if (!result.Parameters || result.Parameters.length === 0) {
        logger.error(`Parameter ${ssmName} was not found in SSM`);
        return "";
      }

      return result.Parameters[0].Value!;
    });
  } else {
    return process.env[envName] || "";
  }
}
