package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestAllowRegistry(t *testing.T) {
	tests := []struct {
		image  string
		expect bool
	}{
		{"evil.io/redis:2.0", false},
		{"127.0.0.1:9874/redis:2.0", false},
		{"registry.replicated.com/library/retraced:v1.3.9", false},
		{"docker.io/redis:2.0", true},
		{"index.docker.io/redis:2.0", true},
		{"ttl.sh/user/kotsadm:12h", true},
		{"gcr.io/redis:2.0", true},
		{"us.gcr.io/redis:2.0", true},
		{"799720048698.dkr.ecr.us-east-1.amazonaws.com/kurl:latest", true},
		{"ghcr.io/redis:2.0", true},
		{"azurecr.io/redis:2.0", true},
	}
	for _, test := range tests {
		t.Run(test.image, func(t *testing.T) {
			got := allowRegistry(test.image)

			assert.Equal(t, test.expect, got)
		})
	}
}
