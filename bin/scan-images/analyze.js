#!/usr/bin/env node

const fs = require('fs');
const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');

const Severities = {
    'negligible': 0,
    'low': 1,
    'medium': 2,
    'high': 3,
    'critical': 4,
};

var analyze = (vulnerabilitiesFilePath, severityThreshold) => {
    const parsed = JSON.parse(fs.readFileSync(vulnerabilitiesFilePath, 'utf-8'));
    const vulnerabilities = [];
    parsed.matches.forEach(match => {
        if (!match.vulnerability.fixedInVersion) {
            return;
        }
        if (Severities[match.vulnerability.severity] < Severities[severityThreshold]) {
            return;
        }
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
        analyze(argv['path'], argv['fail-on']);
    })
    .option('fail-on', {
        type: 'string',
        description: 'fail if a vulnerability is found with a severity >= the given severity',
        choices: ['negligible', 'low', 'medium', 'high', 'critical'],
    })
    .argv;
