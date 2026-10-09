#!/usr/bin/env node

const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');
const { getImages, findLatestAddonVersions, getKubernetesImages } = require('./addons');

const specDir = './addons';
const kubernetesSpecDir = './packages/kubernetes';

var matrix = () => {
    const images = getImages(specDir);
    const addonVersions = findLatestAddonVersions(specDir);
    const filteredImages = images.filter((image) => {
        return addonVersions[image.addon].some((addonVersion) => {
            return addonVersion === image.version;
        });
    });
    const allImages = filteredImages.concat(getKubernetesImages(kubernetesSpecDir));

    // dedupe by image reference: adjacent versions often share the same image
    // tag (e.g. pause, etcd), and scanning the same ref twice adds no signal
    const seen = new Set();
    const deduped = allImages.filter((image) => {
        if (seen.has(image.image)) {
            return false;
        }
        seen.add(image.image);
        return true;
    });

    console.log(JSON.stringify({include: deduped})); // format for git
};

yargs(hideBin(process.argv))
    .command('$0', 'build images matrix', () => {
        matrix();
    })
    .argv;
