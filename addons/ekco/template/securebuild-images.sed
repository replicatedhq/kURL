# Only rewrite image tags already published by SecureBuild.
s@haproxy:3\.4\.6-alpine3\.24(["'[:space:]]|$)@docker.io/kurlsh/haproxy:3.4.6\1@g
