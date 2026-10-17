#!/bin/bash
# Keep the images launched by the CLI aligned with this add-on's offline bundle.
case "${1:-}" in
    run|gen)
        subcommand="$1"
        shift
        exec /usr/local/lib/sonobuoy/sonobuoy "$subcommand" \
            --sonobuoy-image=__SONOBUOY_IMAGE__ \
            --systemd-logs-image=__SYSTEMD_LOGS_IMAGE__ "$@"
        ;;
    *) exec /usr/local/lib/sonobuoy/sonobuoy "$@" ;;
esac
