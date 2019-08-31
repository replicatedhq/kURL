
function tasks() {
    if [ -z "$TASK" ]; then
        return 0
    fi

    case "$TASK" in
        load-images|load_images)
            load_all_images
    esac

    # terminate the script if a task was run
    exit 0
}

function load_all_images() {
    find addons/ packages/ -type f -wholename '*/images/*.tar.gz' | xargs -I {} bash -c "docker load < {}"
}
