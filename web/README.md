This directory holds a web server with an API for creating and serving custom installers.
It relies on a mysql database schema that is not open source, but could be easily inferred from the InstallerStore.

1. Run `make web` from project root to add the templates to this directory
1. Run `make build-cache` in this directory
1. Ensure vandoor skaffold is running
1. Run `skaffold dev -f skaffold.yaml` from project root
