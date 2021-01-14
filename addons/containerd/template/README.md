This directory provides a script to detect available versions of containerd and generate installers for them.
The script runs docker containers for each supported OS and generates a list of containerd versions available >= 1.3.
For each version that is available on all five operating systems it will generate an installer by copying the `base` directory to a version directory.

The Dockerfiles in this directory are used by the script to find available versions of containerd.io and also by the `save-manifest-assets.sh` script that builds the package.
