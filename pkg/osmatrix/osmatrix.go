// Package osmatrix is the single source of truth for kURL's supported operating
// systems. The registry (os-matrix.yaml) declares each OS once — its testgrid
// identity, cloud image, preinit, package family, and capability constraints —
// and every downstream OS-keyed artifact is rendered from it and committed.
//
// See replicatedhq/kURL#6081. Adding a supported OS should be a single registry
// entry plus `make generate-os-matrix`.
package osmatrix

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// PreinitStyle controls how an OS's preinit script is serialized into the
// testgrid OS-definition YAML. It is presentation-only (the two non-empty
// styles yield the same script) but is preserved so regenerated specs are
// byte-identical to the hand-authored originals.
type PreinitStyle string

const (
	// PreinitEmpty renders as: preinit: ""
	PreinitEmpty PreinitStyle = "empty"
	// PreinitQuoted renders as: preinit: "<script>"
	PreinitQuoted PreinitStyle = "quoted"
	// PreinitBlock renders as a literal block scalar (preinit: |).
	PreinitBlock PreinitStyle = "block"
)

// OS is a single supported operating system.
type OS struct {
	// Key uniquely identifies this registry entry. It defaults to ID and only
	// needs to be set when two entries share a testgrid ID but differ (e.g. a
	// pool that pins an older minor version). Pools reference OSes by Key.
	Key string `yaml:"key,omitempty"`

	// Testgrid identity. ID is the id emitted into testgrid specs and may repeat
	// across entries that share it (see Key).
	ID         string `yaml:"id"`
	Name       string `yaml:"name"`
	Version    string `yaml:"version"`
	VMImageURI string `yaml:"vmimageuri"`
	Preinit    string `yaml:"preinit"`

	PreinitStyle PreinitStyle `yaml:"preinitStyle"`

	// Installer identity (for shell predicates / package plumbing). Optional:
	// only OSes that need generated shell/build artifacts set these.
	Distro        string `yaml:"distro,omitempty"`
	VersionMajor  string `yaml:"versionMajor,omitempty"`
	PackageFamily string `yaml:"packageFamily,omitempty"`

	// Capability constraints. These drive computed preflight rules and the
	// capability-derived subset of testgrid unsupportedOSIDs.
	MinKubernetes       string `yaml:"minKubernetes,omitempty"`
	DockerSupported     *bool  `yaml:"dockerSupported,omitempty"`
	ApparmorWorkaround  bool   `yaml:"apparmorWorkaround,omitempty"`
	HostPackagesShipped bool   `yaml:"hostPackagesShipped,omitempty"`

	// BundleDockerfile selects OSes that get a generated parametrized k8s bundle
	// Dockerfile at bundles/k8s-ubuntu<versionMajor><versionMinor>/Dockerfile.
	BundleDockerfile bool `yaml:"bundleDockerfile,omitempty"`
}

// Pool is an ordered list of OS ids that renders to one testgrid OS-spec file
// (testgrid/specs/<name>.yaml). Order and trailing-newline are preserved so the
// rendered file is byte-identical to the committed original.
type Pool struct {
	Name            string   `yaml:"name"`
	IDs             []string `yaml:"ids"`
	TrailingNewline bool     `yaml:"trailingNewline"`
}

// Matrix is the whole registry.
type Matrix struct {
	OSes  []OS   `yaml:"oses"`
	Pools []Pool `yaml:"pools"`

	byKey map[string]*OS
}

// key returns the entry's lookup key (Key, defaulting to ID).
func (o *OS) key() string {
	if o.Key != "" {
		return o.Key
	}
	return o.ID
}

// Parse decodes and validates a registry from YAML bytes.
func Parse(data []byte) (*Matrix, error) {
	var m Matrix
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("unmarshal os-matrix: %w", err)
	}
	if err := m.index(); err != nil {
		return nil, err
	}
	return &m, nil
}

// Load reads and validates a registry from a file path.
func Load(path string) (*Matrix, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read os-matrix %s: %w", path, err)
	}
	return Parse(data)
}

func (m *Matrix) index() error {
	m.byKey = make(map[string]*OS, len(m.OSes))
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.ID == "" {
			return fmt.Errorf("os entry %d has empty id", i)
		}
		k := o.key()
		if _, dup := m.byKey[k]; dup {
			return fmt.Errorf("duplicate os key %q", k)
		}
		switch o.PreinitStyle {
		case PreinitEmpty, PreinitQuoted, PreinitBlock:
		default:
			return fmt.Errorf("os %q has invalid preinitStyle %q", k, o.PreinitStyle)
		}
		m.byKey[k] = o
	}
	for _, p := range m.Pools {
		if p.Name == "" {
			return fmt.Errorf("pool with empty name")
		}
		for _, id := range p.IDs {
			if _, ok := m.byKey[id]; !ok {
				return fmt.Errorf("pool %q references unknown os key %q", p.Name, id)
			}
		}
	}
	return nil
}

// OS returns the OS with the given key (Key, defaulting to ID).
func (m *Matrix) OS(key string) (*OS, bool) {
	o, ok := m.byKey[key]
	return o, ok
}

// Pool returns the pool with the given name.
func (m *Matrix) Pool(name string) (*Pool, bool) {
	for i := range m.Pools {
		if m.Pools[i].Name == name {
			return &m.Pools[i], true
		}
	}
	return nil, false
}
