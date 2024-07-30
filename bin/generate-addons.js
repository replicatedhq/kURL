const fs = require("fs");
const path = require("path");
const semverCompare = require('semver/functions/rcompare')
const AWS = require('aws-sdk');
const installerVersions = require("../web/src/installers/versions");

const ID = process.env.AWS_ACCESS_KEY_ID;
const SECRET = process.env.AWS_SECRET_ACCESS_KEY;
const BUCKET_NAME = process.env.S3_BUCKET;
const FOLDER = process.env.DIST_FOLDER;
const VERSION_TAG = process.env.VERSION_TAG;

const s3 = new AWS.S3({
  accessKeyId: ID,
  secretAccessKey: SECRET
});

const uploadFile = (file) => {
  const fileName = file.split("/")[1];
  const fileContent = fs.readFileSync(file);

  let params = {
    Bucket: BUCKET_NAME,
    Key:  FOLDER + "/" + VERSION_TAG + "/" + fileName,
    Body: fileContent
  };
  s3.upload(params, (err, data) => {
    if (err) throw err;
    console.log("\x1b[32m%s\x1b[0m", "Successfully uploaded " + fileName + " to " + data.Location);
  });

  params = {
    Bucket: BUCKET_NAME,
    Key:  FOLDER + "/" + fileName,
    Body: fileContent
  };
  s3.upload(params, (err, data) => {
    if (err) throw err;
    console.log("\x1b[32m%s\x1b[0m", "Successfully uploaded " + fileName + " to " + data.Location);
  });
}

const preferredVersions = installerVersions.InstallerVersions;
let addons = [];
let supportedVersions = new Object();
const specDir = "./addons";

fs.readdir(specDir, (err, files) => {
  if (err) throw err;
  files.forEach((file) => {
    let sv = [];
    const subDirPath = specDir + "/" + file;
    if (fs.statSync(subDirPath).isDirectory()) {
      const subFiles = fs.readdirSync(subDirPath);
      subFiles.forEach((subFile) => {
        const filepath = path.join(subDirPath, subFile);
        const sf = fs.statSync(filepath);
        if (sf.isDirectory()) {
          if (subFile !== "template" && subFile !== "build-images") {
            sv.push(subFile)
          }
        } else if (sf.isFile()) {
          if (subFile === "categories.json") {
            const content = fs.readFileSync(filepath);
            const addonContent = JSON.parse(content);
            if (typeof addonContent === "object" && Object.entries(addonContent).length !== 0) {
              addons.push(addonContent);
            }
          }
        }
      });

      // Sorting doesn't work if there is an 'alpha' and 'nightly' version (like in kotsadm) so we have to remove it before sorting
      // This is pretty specific to kotsadm so if more add-ons end up with alpha versions we may need to refactor this to support them
      const hasAlphaVersion = sv.includes("alpha");
      const hasNightlyVersion = sv.includes("nightly");

      if (hasAlphaVersion) {
        sv.pop();
      }
      if (hasNightlyVersion) {
        sv.pop();
      }

      // minio tags are not valid semvers
      if (file !== "minio") {
        sv.sort(semverCompare);
      }

      if (hasAlphaVersion) {
        sv.push("alpha");
      }
      if (hasNightlyVersion) {
        sv.push("nightly");
      }

      if (preferredVersions[file]) {
        sv = preferredVersions[file];
      }
      sv.unshift("latest");
      supportedVersions[file] = sv
    }
  });

  supportedVersions.kubernetes = preferredVersions.kubernetes;
  supportedVersions.kubernetes.unshift("latest");

  supportedVersions.fio = ["host"]; // fio serves as a signal that the 'fio' host package should be included

  // Build JSON files
  const addonsFile = {
    _comment: `This file is generated, do not change! Last generated on ${new Date()}. To regenerate run 'make generate-addons'`,
    addOns: addons
  };
  const supportVersionsFile = {
    _comment: `This file is generated, do not change! Last generated on ${new Date()}. To regenerate run 'make generate-addons'`,
    supportedVersions
  }

  // Write finalized JSON files
  fs.writeFile("./addons-gen.json", JSON.stringify(addonsFile), (err) => {
    if (err) throw err;
    console.log("\x1b[34m%s\x1b[0m", "Add-ons generated:", addonsFile.addOns.length);
    console.log("\x1b[32m%s\x1b[0m", "Successfully generated addons-gen.json");

    // Upload files to s3
    uploadFile("./addons-gen.json");
  });
  fs.writeFile("./supported-versions-gen.json", JSON.stringify(supportVersionsFile), (err) => {
    if (err) throw err;
    console.log("\x1b[32m%s\x1b[0m", "Successfully generated supported-versions-gen.json");

    // Upload files to s3
    uploadFile("./supported-versions-gen.json");
  });

});
