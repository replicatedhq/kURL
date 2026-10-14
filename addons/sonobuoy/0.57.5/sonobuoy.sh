#!/bin/bash
# Keep the images launched by the CLI aligned with this add-on's offline bundle.
case "${1:-}" in
    run|gen)
        subcommand="$1"
        shift
        exec /usr/local/lib/sonobuoy/sonobuoy "$subcommand" \
            --sonobuoy-image=docker.io/kurlsh/sonobuoy:v0.57.5 \
            --systemd-logs-image=docker.io/kurlsh/sonobuoy-systemd-logs:v0.4 "$@"
        ;;
    *) exec /usr/local/lib/sonobuoy/sonobuoy "$@" ;;
esac
