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
    // tag (e.g. pause, etcd), and scanning the same ref twice adds no signal.
    // a ref shared with a no-alert add-on (weave, longhorn) must still alert
    // when another consumer of it alerts, so prefer the alerting leg rather
    // than first-wins.
    const byRef = new Map();
    allImages.forEach((image) => {
        const existing = byRef.get(image.image);
        if (!existing || (!existing.alert && image.alert)) {
            byRef.set(image.image, image);
        }
    });
    const deduped = [...byRef.values()];

    console.log(JSON.stringify({include: deduped})); // format for git
};

yargs(hideBin(process.argv))
    .command('$0', 'build images matrix', () => {
        matrix();
    })
    .argv;
