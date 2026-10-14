# Only rewrite image tags already published by SecureBuild.
s@sonobuoy/sonobuoy:v0\.57\.5(["'[:space:]]|$)@docker.io/kurlsh/sonobuoy:v0.57.5\1@g
s@sonobuoy/systemd-logs:v0\.4(["'[:space:]]|$)@docker.io/kurlsh/sonobuoy-systemd-logs:v0.4\1@g
