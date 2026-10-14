# Only rewrite image tags already published by SecureBuild.
s@ghcr\.io/projectcontour/contour:v1\.33\.7(["'[:space:]]|$)@docker.io/kurlsh/contour:v1.33.7\1@g
s@docker\.io/envoyproxy/envoy:distroless-v1\.38\.4(["'[:space:]]|$)@docker.io/kurlsh/envoy:v1.38.4\1@g
s@envoyproxy/envoy:distroless-v1\.38\.4(["'[:space:]]|$)@docker.io/kurlsh/envoy:v1.38.4\1@g
