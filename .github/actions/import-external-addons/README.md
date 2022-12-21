# import-external-addons Action

This action is responsible for polling a list of externally built and hosted add-on versions.

New versions are published to the addon-registry.json and packages are copied from the source and stored in the kURL S3 bucket.

The kURL API merges the addon-registry.json with its internal list of add-on versions, making them available to the end-user.
