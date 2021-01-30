import * as fs from "fs";
import { Installer } from "./src/installers";

fs.writeFileSync("./versions.json", JSON.stringify(Installer.versions));
