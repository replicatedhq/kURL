# Only rewrite image tags already published by SecureBuild.
s@quay\.io/jetstack/cert-manager-controller:v1\.21\.2(["'[:space:]]|$)@docker.io/kurlsh/cert-manager-controller:v1.21.2\1@g
s@quay\.io/jetstack/cert-manager-cainjector:v1\.21\.2(["'[:space:]]|$)@docker.io/kurlsh/cert-manager-cainjector:v1.21.2\1@g
s@quay\.io/jetstack/cert-manager-webhook:v1\.21\.2(["'[:space:]]|$)@docker.io/kurlsh/cert-manager-webhook:v1.21.2\1@g
s@quay\.io/jetstack/cert-manager-acmesolver:v1\.21\.2(["'[:space:]]|$)@docker.io/kurlsh/cert-manager-acmesolver:v1.21.2\1@g
