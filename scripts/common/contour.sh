
function contour() {
    render_yaml contour-common.yaml > /tmp/contour-common.yaml
    render_yaml contour.yaml > /tmp/contour.yaml
    render_yaml contour-rbac.yaml > /tmp/contour-rbac.yaml
    render_yaml contour-service.yaml > /tmp/contour-service.yaml

    kubectl apply -f /tmp/contour-common.yaml
    kubectl apply -f /tmp/contour.yaml
    kubectl apply -f /tmp/contour-rbac.yaml
    kubectl apply -f /tmp/contour-service.yaml
}
