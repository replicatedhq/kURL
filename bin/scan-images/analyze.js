#!/usr/bin/env node

const fs = require('fs');
const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');

const Severities = {
    'unknown': 0,
    'negligible': 1,
    'low': 2,
    'medium': 3,
    'high': 4,
    'critical': 5,
};

var analyze = (vulnerabilitiesFilePath, severityThreshold, whitelistFile) => {
    const parsed = JSON.parse(fs.readFileSync(vulnerabilitiesFilePath, 'utf-8'));
    let whitelist = [];
    if (whitelistFile && fs.existsSync(whitelistFile)) {
        whitelist = JSON.parse(fs.readFileSync(whitelistFile, 'utf-8'));
    };
    const image = parsed.source.target.userInput;
    const vulnerabilities = [];
    parsed.matches.forEach(match => {
        if (!match.vulnerability.fixedInVersion) {
            return;
        }
        if (Severities[match.vulnerability.severity.toLowerCase()] < Severities[severityThreshold.toLowerCase()]) {
            return;
        }
        const vulnStr = `image=${image} artifact=${match.artifact.name} version=${match.artifact.version} fixedInVersion=${match.vulnerability.fixedInVersion} vulnerabilityId=${match.vulnerability.id} ${match.vulnerability.severity}`;
        if (whitelist.some(regex => vulnStr.match(regex))) {
            return;
        };
        vulnerabilities.push({
            'NAME': match.artifact.name,
            'INSTALLED': match.artifact.version,
            'FIXED-IN': match.vulnerability.fixedInVersion,
            'VULNERABILITY': match.vulnerability.id,
            'SEVERITY': match.vulnerability.severity,
        })
    });
    if (vulnerabilities.length) {
        console.table(vulnerabilities);
        console.error('Discovered vulnerabilities with fix versions at or above the severity threshold');
        process.exit(1);
    }
    console.error('No vulnerabilities discovered with fix versions at or above the severity threshold');
};

yargs(hideBin(process.argv))
    .command('$0 [path]', 'analyze vulernabilties.json file', (yargs) => {
        yargs
            .positional('path', {
                describe: 'path to the vulnerabilties json file to parse',
                type: 'string',
                default: './vulnerabilities.json'
            });
    }, (argv) => {
        analyze(argv['path'], argv['fail-on'], argv['whitelist']);
    })
    .option('fail-on', {
        type: 'string',
        description: 'fail if a vulnerability is found with a severity >= the given severity',
        choices: Object.keys(Severities),
        default: 'medium',
    })
    .option('whitelist', {
        type: 'string',
        description: 'path to whitelist json file',
    })
    .argv;
