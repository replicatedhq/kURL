This directory holds a web server with an API for creating and serving custom installers.

# Running Locally
1. Run `make web` from project root to add the templates to this directory
1. Ensure there is a dist folder at project root with a file in it. `mkdir -p dist` and `touch dist/file`.
1. Run `make build-cache` in this directory
1. Run `skaffold dev -f skaffold.yaml` from project root


# Testing Locally
1. Run `npm run api-tests` in this directory once kurl is running locally