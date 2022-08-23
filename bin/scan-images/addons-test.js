const fs = require('fs');

const describe = require('mocha').describe;
const it = require('mocha').it;
const expect = require('chai').expect;

const { findLatestAddonVersions } = require('./addons');

describe("findLatestAddonVersions", () => {
    const versions = findLatestAddonVersions("../../addons");

    it("resolves correct patch version", async () => {
        expect(versions["weave"][0]).to.match(/2.8.1-\d{8}/);;
    });

    it("resolves correct kotsadm version", async () => {
        expect(versions["kotsadm"][0]).to.match(/\d+\.\d+\.\d+/);;
    });

    it("resolves correct minio version", async () => {
        let greatest = "";
        fs.readdirSync("../../addons/minio").forEach((file) => {
            if (!file.match(/\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z/)) {
                return;
            }
            // alphabetical
            if (file > greatest) {
                greatest = file;
            }
        });
        expect(versions["minio"][0]).to.equal(greatest);;
    });

    it("does not contain rookupgrade", async () => {
        expect(Object.keys(versions)).not.to.include("rookupgrade");
    });
});
