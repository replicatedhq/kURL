const fs = require('fs');
const path = require('path');
const semver = require('semver');

const skipAddons = [
    "rookupgrade", "kotsadm",
];

// noAlertAddons are scanned but must not fail the workflow.
// Deprecated add-ons (weave, longhorn) are frozen upstream and will never
// receive fixes, so their CVEs would keep the workflow red forever.
// Every other image fails the build when grype finds a fixable High+ CVE,
// whether or not we maintain it - customers run all of them.
const noAlertAddons = ["weave", "longhorn"];

// kubernetesMinorTracks is how many of the newest Kubernetes minor tracks get
// their images scanned (latest patch version of each), mirroring the rolling
// support window maintained by update-kubernetes.yaml.
const kubernetesMinorTracks = 4;
const kubernetesSpecDir = './packages/kubernetes';

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
            fs.readFileSync(manifestFile, 'utf-8').split(/\r?\n/).forEach((line) => {
                const parts = line.split(' ');
                if (parts[0] !== 'image') {
                    return;
                }
                const name = parts[1];
                let imageName = parts[2];
                if (imageName.split('/').length === 1) {
                    imageName = `library/${imageName}`
                }
                const image = {
                    addon: addon,
                    version: version,
                    name: name,
                    image: imageName,
                    alert: !noAlertAddons.includes(addon),
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

// getKubernetesImages returns the images of the latest patch version of each
// of the newest kubernetesMinorTracks minor tracks under packages/kubernetes.
// This covers the kubeadm-managed images (etcd, CoreDNS, pause, kube-proxy,
// the control plane) that add-on manifests never reference.
var getKubernetesImages = rootDir => {
    const versions = fs.readdirSync(rootDir).filter((version) => {
        return semver.valid(version) && fs.existsSync(path.join(rootDir, version, 'Manifest'));
    });

    // latest patch version per minor track
    const byTrack = {};
    versions.forEach((version) => {
        const track = `${semver.major(version)}.${semver.minor(version)}`;
        if (!byTrack[track] || semver.gt(version, byTrack[track])) {
            byTrack[track] = version;
        }
    });

    const tracks = Object.keys(byTrack)
        .sort((a, b) => semver.rcompare(`${a}.0`, `${b}.0`))
        .slice(0, kubernetesMinorTracks);

    const images = [];
    tracks.forEach((track) => {
        const version = byTrack[track];
        fs.readFileSync(path.join(rootDir, version, 'Manifest'), 'utf-8').split(/\r?\n/).forEach((line) => {
            const parts = line.split(' ');
            if (parts[0] !== 'image') {
                return;
            }
            images.push({
                addon: 'kubernetes',
                version: version,
                name: parts[1],
                image: parts[2],
                alert: true,
            });
        });
    });
    return images;
};

module.exports = { getImages, findLatestAddonVersions, getKubernetesImages };
