import * as fs from "fs";
import { InstallerVersions } from "./src/installers/versions";

fs.writeFileSync("./versions.json", JSON.stringify(InstallerVersions));
