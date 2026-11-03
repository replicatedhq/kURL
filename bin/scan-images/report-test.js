const describe = require('mocha').describe;
const it = require('mocha').it;
const expect = require('chai').expect;

const { summarize, buildMessage } = require('./report');

const match = (id, severity) => ({ vulnerability: { id, severity } });

describe("summarize", () => {
    const results = [
        {
            meta: { addon: "calico", version: "3.9.1", image: "calico/node:v3.9.1", alert: true },
            grype: { matches: [
                match("CVE-1", "High"),
                match("CVE-1", "High"), // same CVE in a second package
                match("CVE-2", "Critical"),
                match("CVE-3", "Medium"),
            ] },
        },
        {
            meta: { addon: "contour", version: "1.33.7", image: "contour:v1.33.7", alert: true },
            grype: { matches: [match("CVE-4", "Critical"), match("CVE-5", "Critical")] },
        },
        {
            meta: { addon: "weave", version: "2.8.1", image: "weave-kube:2.8.1", alert: false },
            grype: { matches: [match("CVE-6", "Critical")] },
        },
        {
            meta: { addon: "fluentd", version: "1.7.4", image: "busybox:1", alert: true },
            grype: { matches: [match("CVE-7", "Low")] },
        },
    ];
    const images = summarize(results);

    it("counts unique CVEs per severity", () => {
        const calico = images.find((image) => image.addon === "calico");
        expect(calico.critical).to.equal(1);
        expect(calico.high).to.equal(1);
    });

    it("skips no-alert add-ons and images without high or critical findings", () => {
        expect(images.map((image) => image.addon)).to.deep.equal(["contour", "calico"]);
    });
});

describe("buildMessage", () => {
    it("includes totals, the run link and one line per image", () => {
        const message = buildMessage([
            { addon: "contour", version: "1.33.7", image: "contour:v1.33.7", critical: 2, high: 0 },
            { addon: "calico", version: "3.9.1", image: "calico/node:v3.9.1", critical: 1, high: 1 },
        ], "https://example.com/run");
        expect(message).to.contain("3 critical / 1 high fixable CVEs across 2 images");
        expect(message).to.contain("<https://example.com/run|workflow run>");
        expect(message).to.contain("• `calico/node:v3.9.1` (calico 3.9.1): 1 critical, 1 high");
    });
});

describe("failed scans", () => {
    const images = summarize([
        { meta: { addon: "contour", version: "1.33.7", image: "contour:v1.33.7", alert: true }, grype: null },
        { meta: { addon: "longhorn", version: "1.3.1", image: "longhorn-ui:v1.3.1", alert: false }, grype: null },
    ]);

    it("keeps alerting images whose scan produced no output", () => {
        expect(images).to.have.lengthOf(1);
        expect(images[0].error).to.equal(true);
    });

    it("lists them separately from the CVE counts", () => {
        const message = buildMessage(images, "https://example.com/run");
        expect(message).to.contain("0 critical / 0 high fixable CVEs across 0 images");
        expect(message).to.contain("1 scan didn't finish");
        expect(message).to.contain("• `contour:v1.33.7` (contour 1.33.7)");
    });
});
