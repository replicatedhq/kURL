# TestGrid Branch Support 

As automated PRs come in for Kurl features, such as add-on upgrades, there also needs to be testing automation in place to have confidence in the changes without manual testing. 
This proposal suggest how to extend TestGrid to support execution against branches and github actions that will initiate `tgrun` against the PR branch.


## Goals
- Enable TestGrid to work against any branch.
- Provide good test coverage of changes with as little unnecessary testing as possible.

## Non Goals

- Automating kurl addon create or upgrades (see [PR-1014](https://github.com/replicatedhq/kURL/pull/1014) )

## Background

As of today TestGrid runs nightly (prod), on merge to master (staging) and on-demand using `tgrun`.
All this happens against the master branch and runs through the productions testgrid.kurl.sh server.
The `tgrun` cli uses kurl.sh to generate a unique kurl installer for each run instance, and run instances use kurl.sh and the distribution packages in S3 to execute the test.   

![TestGrid Diagram](./assets/Testgrid%20Nighty.png)

Scenarios to address:
1. Automated addon update
1. Testing a new addon
1. K8S update (automated?)

Problems that needed to be addressed in the design:
1. Where will untested/alpha packages live, and how do they get there?
1. Which environment(s) do PR TestGrid runs execute against?
1. How to get a Kurl installer for packages that aren't yet supported (i.e. break validation)?
1. How navigate addons being hard-coded in tools and scripts?

## High-Level Design

Use the following environments:
1. Use Prod TestGrid for executing PR tests
1. Use staging.kurl.sh for installers

Code changes that are required:
1. The Kurl installer spec will be updated to allow installers to be generated with `upsteam_override`.
1. kurl.sh will be modified to allow any version for an addon in the spec with the `upstream_override` enabled.
1. `tgrun` will be updated
   1. Since this proposal will only really test updated addons, a flag to run only a single "latest" kurl installer against all OSes.
   1. Flags to specify addon version and download url
1. Modify install.sh to use `upstream_override` bucket path from the kurl spec.
   1. Possibly modify `yamltobash` utils (and others?)
1. Add a github action to run on a PR creation/update.
   1. Do a diff and see if any of the addon dirs have been modified.
   1. Push packages to `<s3>/pr` for modified dirs (wait?)
   1. `tgrun queue --ref=<short commit>-pr-<#> --latest-only --version-override=contour=1.12.0 --s3-override=contour=<s3 url in previous step>`
   1. (Optional) Poll results and/or add TestGrid url in PR.

### Limitations
1. This process won't work for new addons or changes to the actual installer scripting.
    1. The kurl.sh script and `yamltobash` need to be changed here and served somewhere that can be access for each test instance config.
1. Can't expect 'latest' test configuration to resolve to the newest config
    1. Latest is interpreted by kurl.sh api using hardcoded values.

## Detailed Design

Updated Kurl Installer Spec to get around validation on kurl.sh (Courtesy @lavery):
```yaml
apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata: 
  name: "latest"
spec: 
  kubernetes: 
    version: "latest"
  weave: 
    version: "latest"
  rook: 
    version: "latest"
  contour: 
    version: "latest"
    s3-override: "<bucket-url>/pr/<commit hash>-contour-1.11.0.tar.gz"
  ...
```

## Testing

Initial testing will be challenging considering it requires changes to a lot of the components. 
Proposing to break this up into these PRs to mitigate risk and manage code review:
- Change kurl.sh web to adopt new kurl spec, run test suite.
- Modify `tgrun` with proposed changes, test that kurl.sh install fail for the new spec format. 
- Thorough manual testing for changes to install.sh that pull from the repository.
- Attempt an addon upgrade and see that the GH action produces the desired affect.

Regressions should be detected  quickly as this will run as part of the PR process on the repo. 

## Alternatives Considered

1. Deploy a PR version of kurl.sh and testgrid.kurl.sh 
    1. This could resolve a lot of the limitations mentioned above since it would be a e2e test in a closed ecosystem 
    1. Adds a lot more technical complexity on top of just having TestGrid runs 
2. Also considered some of the following shortcuts to prevent any changes to kurl.sh or the installer spec, but generally would be messy. 
    1. Instead of an endpoint `kurl.sh/installer/unsafe` that stores a kurl spec with no validation.
    1. Adding/overwriting alpha packages directly into S3 at `/staging` would obviate the need for changes to the installer scripts to pull new packages, but potentially pollute the staging directory with alpha artifacts.

## Security Considerations

None.
The proposed changes shouldn't compromise the Kurl S3 buckets or Kurl installer integrity.


(Thanks to vmware-tanzu/velero for this design template)