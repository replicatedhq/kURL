#!/usr/bin/env node

const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');
const { getImages, findLatestAddonVersions } = require('./addons');

const specDir = './addons';

var matrix = () => {
    const images = getImages(specDir);
    const addonVersions = findLatestAddonVersions(specDir);
    const filteredImages = images.filter((image) => {
        return addonVersions[image.addon].some((addonVersion) => {
            return addonVersion === image.version;
        });
    });
    console.log(JSON.stringify({include: filteredImages})); // format for git
};

yargs(hideBin(process.argv))
    .command('$0', 'build images matrix', () => {
        matrix();
    })
    .argv;
