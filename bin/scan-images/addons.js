const fs = require('fs');
const semver = require('semver');

const skipAddons = [
    "rookupgrade",
];

var getImages = rootDir => {
    const images = [];
    fs.readdirSync(rootDir).forEach((addon) => {
        if (skipAddons.includes(addon)) {
            return;
        }

        const addonDir = `${rootDir}/${addon}`;
        const stats = fs.statSync(addonDir);
        if (!stats.isDirectory()) {
            return;
        }
        fs.readdirSync(addonDir).forEach((version) => {
            const versionDir = `${rootDir}/${addon}/${version}`;
            const stats = fs.statSync(versionDir);
            if (!stats.isDirectory()) {
                return;
            }
            const manifestFile = `${rootDir}/${addon}/${version}/Manifest`;
            if (!fs.existsSync(manifestFile)) {
                return;
            }
            const trivyignoreFile = `${rootDir}/${addon}/${version}/.trivyignore.rego`;
            let trivyignore = '';
            if (fs.existsSync(trivyignoreFile)) {
                trivyignore = Buffer.from(fs.readFileSync(trivyignoreFile, 'utf-8')).toString('base64'); // remove newlines
            }
            fs.readFileSync(manifestFile, 'utf-8').split(/\r?\n/).forEach((line) => {
                const parts = line.split(' ');
                if (parts[0] !== 'image') {
                    return;
                }
                let imageName = parts[2];
                if (imageName.split('/').length === 1) {
                    imageName = `library/${imageName}`
                }
                const image = {
                    addon: addon,
                    version: version,
                    name: parts[1],
                    image: imageName,
                    trivyignore: trivyignore,
                };
                images.push(image);
            });
        });
    });
    return images;
};

var findLatestAddonVersions = rootDir => {
    const versions = {};
    fs.readdirSync(rootDir).forEach((addon) => {
        if (skipAddons.includes(addon)) {
            return;
        }

        const addonDir = `${rootDir}/${addon}`;
        const stats = fs.statSync(addonDir);
        if (!stats.isDirectory()) {
            return;
        }

        versions[addon] = [];

        // this loop finds the greatest version and adds it if it is not in the latest spec
        let greatestVersion = '';
        let greatestVersionClean = '';
        let foundSemver = false;
        fs.readdirSync(addonDir).some((version) => {
            const versionDir = `${rootDir}/${addon}/${version}`;
            const stats = fs.statSync(versionDir);
            if (!stats.isDirectory()) {
                return false;
            }
            const manifestFile = `${rootDir}/${addon}/${version}/Manifest`;
            if (!fs.existsSync(manifestFile)) {
                return false;
            }
            if (semver.valid(version)) {
                foundSemver = true // kotsadm has semver and non-semver versions such as "nightly"
                let clean = version.replace(/\.0(\d)\./, ".$1."); // fix docker versions e.g. 19.03.15
                if (["weave", "rook"].includes(addon)) {
                    clean = clean.replace(/(\d+\.\d+\.\d+)-/, "$1+"); // we have a bad habit of using prerelease identifier as a patch which resolves lower e.g. weave 2.8.1-20220720
                }
                if (!greatestVersion || semver.gte(clean, greatestVersionClean)) {
                    greatestVersion = version;
                    greatestVersionClean = clean;
                }
            } else if (!foundSemver && version > greatestVersion) {
                greatestVersion = version;
            }
        });

        if (greatestVersion) {
            versions[addon].push(greatestVersion);
        }
    });
    return versions;
};

module.exports = { getImages, findLatestAddonVersions };
