package main

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v2"
)

func Test_mergeDockerConfigData(t *testing.T) {
	tests := []struct {
		name      string
		oldConfig []byte
		newConfig []byte
		want      []byte
		wantError bool
	}{
		{
			name:      "both configs are empty",
			oldConfig: nil,
			newConfig: nil,
			want:      nil,
			wantError: false,
		},
		{
			name:      "old config is empty",
			oldConfig: nil,
			newConfig: []byte(`{"key": "newVal"}`),
			want:      []byte(`{"key": "newVal"}`),
			wantError: false,
		},
		{
			name:      "new config is empty",
			oldConfig: []byte(`{"key": "oldVal"}`),
			newConfig: nil,
			want:      []byte(`{"key": "oldVal"}`),
			wantError: false,
		},
		{
			name: "both config are non-empty",
			oldConfig: []byte(`{
  "oldKey": "oldVal",
  "commonKey1": {"subKey1": "oldVal1", "subKey2": "oldVal2"}
}`),
			newConfig: []byte(`{
  "oldKey": "newVal",
  "commonKey1": {"subKey2": "newVal2"}
}`),
			want: []byte(`{
  "oldKey": "newVal",
  "commonKey1": {"subKey1": "oldVal1", "subKey2": "newVal2"}
}`),
			wantError: false,
		},

		{
			name:      "old config is empty json",
			oldConfig: []byte(`{}`),
			newConfig: []byte(`{
  "newKey": "oldVal",
  "commonKey1": {"subKey2": "newVal2"}
}`),
			want: []byte(`{
  "newKey": "oldVal",
  "commonKey1": {"subKey2": "newVal2"}
}`),
			wantError: false,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := require.New(t)

			mergedConfig, err := mergeDockerConfigData(test.oldConfig, test.newConfig)
			if test.wantError {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			var mergedMap, wantMap interface{}
			_ = json.Unmarshal(mergedConfig, &mergedMap)
			_ = json.Unmarshal(test.want, &wantMap)
			assert.Equal(t, wantMap, mergedMap)
		})
	}
}

func Test_mergeYamlConfigData(t *testing.T) {
	tests := []struct {
		name      string
		oldConfig []byte
		newConfig []byte
		want      []byte
		wantError bool
	}{
		{
			name:      "both configs are empty",
			oldConfig: nil,
			newConfig: nil,
			want:      nil,
			wantError: false,
		},
		{
			name:      "old config is empty",
			oldConfig: nil,
			newConfig: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "old"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"`),
			want: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "old"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"`),
			wantError: false,
		},
		{
			name: "new config is empty",
			oldConfig: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "old"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"`),
			want: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "old"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"`),
			newConfig: nil,
			wantError: false,
		},
		{
			name: "both config are non-empty",
			oldConfig: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "old"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"`),
			newConfig: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "base"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  fluentd:
    fullEFKStack: true`),
			want: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "merged"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"
  fluentd:
    fullEFKStack: true`),
			wantError: false,
		},
		{
			name: "merges daemon.json properly",
			oldConfig: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "old"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  contour:
    version: "1.0.1"
  docker:
    version: "latest"
    bypassStorageDriverWarnings: true
    hardFailOnLoopback: true
    noCEOnEE: true
    daemonConfig: >
      {
        "log-opts": {
          "max-size": "50m",
          "max-file":"10",
          "labels": "dmitriy-test",
          "env": "os,customer"
        },
        "mtu": 0,
        "max-concurrent-uploads": 5,
        "shutdown-timeout": 15,
        "debug": true,
        "hosts": ["1"],
        "tlscacert": "poop",
        "oom-score-adjust": -500,
        "runtimes": {
          "runc": {
          "path": "runc"
          },
          "custom": {
          "path": "/usr/local/bin/my-runc-replacement",
          "runtimeArgs": [
            "--debug"
          ]
          }
        }
      }`),
			newConfig: []byte(`apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata:
  name: "base"
spec:
  kubernetes:
    version: "latest"
    serviceCIDR: ""
  docker:
    version: "latest"
    bypassStorageDriverWarnings: true
    hardFailOnLoopback: true
    noCEOnEE: false
    daemonConfig: >
      {
        "log-opts": {
          "mike-test": "yo",
          "max-size": "9000m"
        },
        "mtu": 2,
        "max-concurrent-uploads": 5,
        "shutdown-timeout": 15,
        "debug": true,
        "hosts": ["2", "3"],
        "blah": "yo",
        "oom-score-adjust": -500,
        "runtimes": {
          "runc": {
          "path": "runc"
          },
          "custom": {
          "path": "/usr/local/bin/mike",
          "runtimeArgs": [
          ]
          }
        }
      }
  fluentd:
    fullEFKStack: true`),
			want: []byte(`apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: merged
spec:
  contour:
    version: 1.0.1
  docker:
    bypassStorageDriverWarnings: true
    daemonConfig: |-
      {
        "blah": "yo",
        "debug": true,
        "hosts": [
          "2",
          "3"
        ],
        "log-opts": {
          "env": "os,customer",
          "labels": "dmitriy-test",
          "max-file": "10",
          "max-size": "9000m",
          "mike-test": "yo"
        },
        "max-concurrent-uploads": 5,
        "mtu": 2,
        "oom-score-adjust": -500,
        "runtimes": {
          "custom": {
            "path": "/usr/local/bin/mike",
            "runtimeArgs": []
          },
          "runc": {
            "path": "runc"
          }
        },
        "shutdown-timeout": 15,
        "tlscacert": "poop"
      }
    hardFailOnLoopback: true
    noCEOnEE: false
    version: latest
  fluentd:
    fullEFKStack: true
  kubernetes:
    serviceCIDR: ""
    version: latest`),
			wantError: false,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := require.New(t)

			mergedConfig, err := mergeYamlConfigData(test.oldConfig, test.newConfig)
			if test.wantError {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			var mergedMap, wantMap interface{}
			_ = yaml.Unmarshal(mergedConfig, &mergedMap)
			_ = yaml.Unmarshal(test.want, &wantMap)
			assert.Equal(t, wantMap, mergedMap)
		})
	}
}
