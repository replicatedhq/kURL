#!/usr/bin/env bash

function nginx_pre_init() {
    if [ -z "$NGINX_HTTP_PORT" ]; then
        NGINX_HTTP_PORT="80"
    fi

    if [ -z "$NGINX_HTTPS_PORT" ]; then
        NGINX_HTTPS_PORT="443"
    fi
}

function nginx() {
    local src="$DIR/addons/nginx/1.0.4"
    local dst="$DIR/kustomize/nginx"

    cp "$src/nginx.yaml" "$dst"
    cp "$src/kustomization.yaml" "$dst"

    semverCompare "$KUBERNETES_VERSION" "1.20.0"
    if [ "$semver_compare_result" = "-1" ]; then
        render_yaml_file "$src/tmpl-ipv4-service-patch.yaml" > "$dst/service-patch.yaml"
    else
        render_yaml_file "$src/tmpl-service-patch.yaml" > "$dst/service-patch.yaml"
    fi

    kubectl apply -k "$dst"
}
