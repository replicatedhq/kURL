#!/usr/bin/env node

const fs = require('fs');
const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');
const { InstallerVersions } = require('../../web/src/installers/versions');

const specDir = './addons';

var getImages = () => {
    const images = [];
    fs.readdirSync(specDir).forEach((addon) => {
        const addonDir = `${specDir}/${addon}`;
        const stats = fs.statSync(addonDir);
        if (!stats.isDirectory()) {
            return;
        }
        fs.readdirSync(addonDir).forEach((version) => {
            const versionDir = `${specDir}/${addon}/${version}`;
            const stats = fs.statSync(versionDir);
            if (!stats.isDirectory()) {
                return;
            }
            const manifestFile = `${specDir}/${addon}/${version}/Manifest`;
            if (!fs.existsSync(manifestFile)) {
                return;
            }
            fs.readFileSync(manifestFile, 'utf-8').split(/\r?\n/).forEach((line) => {
                const parts = line.split(' ');
                if (parts[0] !== 'image') {
                    return;
                }
                const image = {addon: addon, version: version, name: parts[1], image: parts[2]};
                images.push(image);
            });
        });
    });
    return images;
};

var findLatestAddonVersions = () => {
    const versions = {};
    fs.readdirSync(specDir).forEach((addon) => {
        const addonDir = `${specDir}/${addon}`;
        const stats = fs.statSync(addonDir);
        if (!stats.isDirectory()) {
            return;
        }
        if (addon in InstallerVersions) {
            if (InstallerVersions[addon].includes('alpha')) {
                versions[addon] = 'alpha';
                return;
            }
            versions[addon] = InstallerVersions[addon][0];
            return;
        }
        // this loop finds the last version directory
        fs.readdirSync(addonDir).reverse().some((version) => {
            const versionDir = `${specDir}/${addon}/${version}`;
            const stats = fs.statSync(versionDir);
            if (!stats.isDirectory()) {
                return false;
            }
            const manifestFile = `${specDir}/${addon}/${version}/Manifest`;
            if (fs.existsSync(manifestFile)) {
                versions[addon] = version;
                return true;
            }
            return false;
        });
    });
    return versions;
};

var matrix = () => {
    const images = getImages();
    const addonVersions = findLatestAddonVersions();
    const filteredImages = images.filter((image) => {
        return addonVersions[image.addon] === image.version;
    });
    console.log(JSON.stringify({include: filteredImages})); // format for git
};

yargs(hideBin(process.argv))
    .command('$0', 'build images matrix', () => {
        matrix();
    })
    .argv;
