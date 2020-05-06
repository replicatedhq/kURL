# Replace the current typescript kurl.sh api for creating installers with a go api using gin
 
This proposal outlines the benefits and challenges of replacing the current typescript api with a more simple golang api.

## Goals

- Significantly reduce code complexety around making changes to the installer type
- Provide type safety and validation for POSTed installers

## Non Goals

- Create an API for kurlkinds dsecriptions. This probably best suited in the kurl.sh site repo as it is not core functionality of the api.

## Background

Previously, kURL has used the backend typescript api to take a yaml config and make an install script with options and bash variables set for the install.
With the recent changes to kURL such as the addition of the CRD, the current install script uses go binaries to parse and traverse the yaml tree to set options.

We can greatly reduce code complexity from the no longer used parts of the typescript api and gain added type safety by moving this api to Go.

## High-Level Design

Endpoints

postInstaller POST /installer
putInstaller PUT /installer/{name}
getInstallScript GET /{installerID}
getJoinScript GET /{installerID}/join.sh
getUpgradeScript GET /{installerID}/upgrade.sh
getInstallerYaml GET /installer/{installerID}
validateInstaller POST /installer/validate
getBundle GET/bundle/{installerID}

## Detailed Design

postInstaller Endpoint:
The function will take a yaml Installer and attempt to unmarshall it into an Installer CRD.
If the unmarshalling fails, an error will be retuned. If the marshalling succeeds the version of an addon will be checked against existing versions.
If the version is not found an error will be returned.
Any version latest will be converted to the most recent version.
There will also be other validation steps and can be more in the future, right now changing the CIDR range for serviceCIDR and podCIDR will be needed.

putInstaller Endpoint
This endpoint will take yaml installer, do the validation as done inpostInstaller, and update that installer in the db.
This endpoint will also handle JWT auth in order to validate the creater of the installer. 

getInstallScript, getJoinScript, getUpgradeScript Endpoints:
These will check the db for a specific installerID, and inject it into the script as INSTALLER_SPEC_YAML bash strings

validateInstaller Endpoint:
This endpoint will take a yaml file and do the steps similar to postInstaller Endpoint and return a response indicating if it is invalid or not.

getBundle Endpoint:
This is already served by a golang endpoint
This calls the typescript API to get the scripts and the list of packages to push into the bundle and needs to be addressed

## Legacy Considerations

Currently, the way a url/installer hash is calculated is to take the oldstyle installflags and concat them together into a single string that is fed into a sha256 hash function, the output converted into a hexidecimal string, with the result truncated to 7 chars (there are roughly 268 million possibilities)

Additionally, due to legacy considerations there are certain values that are added to the string before others.

This result can be duplicated in Golang, but it probably make sense to change this to a similar format to that used in the parsing binaries for ease of use so things do not need to be updated by hand.
However, this will mean that existing yaml will now hash to a different value.
If we keep all existing installerID hashes in the DB, we can maintain backwards compatibility.

Additionally, to maintain backwards compatibility some shimming of old yaml spec where old was converted into new occurs.
This will fail unmarshalling and would have to be deprecated or a workaround created.

## Monitoring Considerations

SIGSCI_RPC_ADDRESS
BUGSNAG_KEY
other monitoring considerations
