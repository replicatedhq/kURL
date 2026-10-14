# Only rewrite image tags already published by SecureBuild.
s@registry\.k8s\.io/pause:3\.10(["'[:space:]]|$)@docker.io/kurlsh/pause:3.10\1@g
