# Only rewrite image tags already published by SecureBuild.
s@registry\.k8s\.io/metrics-server/metrics-server:v0\.9\.0(["'[:space:]]|$)@docker.io/kurlsh/metrics-server:v0.9.0\1@g
