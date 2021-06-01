package main

import (
	"testing"

	"github.com/pelletier/go-toml"
	"github.com/stretchr/testify/assert"
)

func TestListLeaves(t *testing.T) {
	var treeString = `
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    systemd_cgroup = false
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v1"`
	tree, err := toml.Load(treeString)
	if err != nil {
		t.Fatal(err)
	}

	expect := [][]string{
		{"plugins", "io.containerd.grpc.v1.cri", "containerd", "runtimes", "runc", "runtime_type"},
		{"plugins", "io.containerd.grpc.v1.cri", "systemd_cgroup"},
	}
	actual := listLeaves(tree)

	for _, leaf := range expect {
		assert.Contains(t, actual, leaf)
	}
}

func TestMerge(t *testing.T) {
	base := `
version = 2

[debug]
  level = ""

[timeouts]
  "io.containerd.timeout.shim.cleanup" = "5s"
  "io.containerd.timeout.shim.load" = "5s"
  "io.containerd.timeout.shim.shutdown" = "3s"
  "io.containerd.timeout.task.state" = "2s"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    systemd_cgroup = false
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v1"`

	patch := `
[debug]
  level = "warn"
[plugins."io.containerd.grpc.v1.cri"]
  systemd_cgroup = true
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"`

	baseTree, err := toml.Load(base)
	if err != nil {
		t.Fatal(err)
	}

	patchTree, err := toml.Load(patch)
	if err != nil {
		t.Fatal(err)
	}

	merge(baseTree, patchTree)

	assert.Equal(t, "warn", baseTree.GetPath([]string{"debug", "level"}))
	assert.Equal(t, true, baseTree.GetPath([]string{"plugins", "io.containerd.grpc.v1.cri", "systemd_cgroup"}))
	assert.Equal(t, "io.containerd.runc.v2", baseTree.GetPath([]string{"plugins", "io.containerd.grpc.v1.cri", "containerd", "runtimes", "runc", "runtime_type"}))
}
