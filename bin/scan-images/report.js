#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// reportSeverities matches the --fail-on high threshold in the scan workflow.
const reportSeverities = ['Critical', 'High'];

// loadResults reads the per-image scan artifacts downloaded by the
// collect-results job. Each artifact directory holds the grype.json output
// and a meta.json copy of the matrix entry that produced it. grype.json is
// empty when the scan itself errored (e.g. the grype db download failed), so
// those come back with grype set to null.
const loadResults = (dir) => {
    return fs.readdirSync(dir, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => path.join(dir, entry.name))
        .filter((d) => fs.existsSync(path.join(d, 'meta.json')))
        .map((d) => {
            let grype = null;
            try {
                grype = JSON.parse(fs.readFileSync(path.join(d, 'grype.json')));
            } catch (err) {
                // leave grype null so the image is reported as a failed scan
            }
            return { meta: JSON.parse(fs.readFileSync(path.join(d, 'meta.json'))), grype };
        });
};

// summarize counts unique fixable CVEs per severity for each alerting image.
// No-alert add-ons (weave, longhorn) are left out so the report only carries
// findings that actually failed the scan. Images whose scan produced no
// output are flagged with error so they don't drop out of the report.
const summarize = (results) => {
    return results
        .filter((result) => result.meta.alert)
        .map((result) => {
            const image = {
                addon: result.meta.addon,
                version: result.meta.version,
                image: result.meta.image,
            };
            if (!result.grype) {
                return { ...image, error: true, critical: 0, high: 0 };
            }
            const ids = {};
            reportSeverities.forEach((severity) => ids[severity] = new Set());
            (result.grype.matches || []).forEach((match) => {
                const severity = match.vulnerability.severity;
                if (ids[severity]) {
                    ids[severity].add(match.vulnerability.id);
                }
            });
            return { ...image, critical: ids['Critical'].size, high: ids['High'].size };
        })
        .filter((image) => image.error || image.critical + image.high > 0)
        .sort((a, b) => b.critical - a.critical || b.high - a.high || a.image.localeCompare(b.image));
};

const plural = (count, word) => `${count} ${word}${count === 1 ? '' : 's'}`;

// buildMessage renders the Slack mrkdwn report for an incoming webhook.
const buildMessage = (images, runUrl) => {
    const found = images.filter((image) => !image.error);
    const failed = images.filter((image) => image.error);
    const critical = found.reduce((sum, image) => sum + image.critical, 0);
    const high = found.reduce((sum, image) => sum + image.high, 0);
    const lines = [
        `:rotating_light: *kURL CVE scan:* ${critical} critical / ${high} high fixable CVEs across ${plural(found.length, 'image')} (<${runUrl}|workflow run>)`,
    ];
    if (found.length > 0) {
        lines.push('');
        found.forEach((image) => {
            lines.push(`• \`${image.image}\` (${image.addon} ${image.version}): ${image.critical} critical, ${image.high} high`);
        });
    }
    if (failed.length > 0) {
        lines.push('', `:warning: ${plural(failed.length, 'scan')} didn't finish, check the job logs:`);
        failed.forEach((image) => {
            lines.push(`• \`${image.image}\` (${image.addon} ${image.version})`);
        });
    }
    return lines.join('\n');
};

// No third-party deps on purpose: this runs in the job that holds the Slack
// webhook secret, so it doesn't install anything from npm.
if (require.main === module) {
    const usage = 'usage: report.js <dir> --run-url <url>';
    const args = process.argv.slice(2);
    const flag = args.indexOf('--run-url');
    const runUrl = flag >= 0 ? args[flag + 1] : undefined;
    const dir = args.find((arg, i) => !arg.startsWith('--') && i !== flag + 1);
    if (!dir || !runUrl) {
        console.error(usage);
        process.exit(1);
    }
    const images = summarize(loadResults(dir));
    if (images.length > 0) {
        console.log(JSON.stringify({ text: buildMessage(images, runUrl) }));
    }
}

module.exports = { loadResults, summarize, buildMessage };
