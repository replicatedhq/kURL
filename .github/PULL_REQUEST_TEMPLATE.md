<!--  Thanks for sending a pull request!  Here are some tips for you:

1. If this is your first time, please read our contributor guidelines here:
https://github.com/replicatedhq/kURL/blob/main/CONTRIBUTING.md.
2. If the PR is unfinished, please mark it as a draft.
3. Set the label on the pull request.
-->

#### What this PR does / why we need it:

#### Which issue(s) this PR fixes:
<!--
*Automatically closes linked issue when PR is merged.
Usage: `Fixes #<issue number>`, or `Fixes (paste link of issue)`.
-->
Fixes #

#### Special notes for your reviewer:
<!--
Any additional special notes for your reviewer.
-->

## Steps to reproduce
<!---
Please provide minimum instructions for how someone can view/test/verify your changes.
-->

#### Does this PR introduce a user-facing change?
<!--
Write "NONE" in any release-note block below that does not apply.
If yes, a release note is required:
-->
New features:
```release-notes-features

```

Bug fixes:
```release-notes-fixes

```

Improvements:
```release-notes-improvements

```

#### Does this PR require documentation?
<!--
If no, just write "NONE" below.
If yes, link to the related https://github.com/replicatedhq/kurl.sh documentation PR:
-->

#### Does this PR need a kURL-api compatibility rule?
<!--
kURL-api rejects installer specs that kURL cannot install. A rule is needed when this PR adds a
Kubernetes or add-on version that cannot be installed with some Kubernetes or add-on versions, or adds
a `bail` or preflight failure for a combination of versions or settings.
Kubernetes and add-on version pairs go in `Installer.addonKubernetesRules` in kURL-api
`src/installers/index.ts`, and other combinations in `validateCompatibility()`, with tests in
`src/test/installers/compatibility-test.ts`.
kURL-api is private. If you cannot open it, describe the combination here and a maintainer will add
the rule.
-->
- [ ] kURL-api rule: (link the kURL-api PR, describe the combination to reject, or write NONE)
