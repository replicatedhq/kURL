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
	"regexp"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

// Field validation patterns. Every scalar that gets interpolated into a
// generated shell script, Dockerfile, YAML document, or a write path must be
// constrained at the registry boundary so a crafted os-matrix.yaml value cannot
// inject into generated output (Go's %q does not escape $ or backtick, and
// several render sites concatenate raw). See replicatedhq/kURL#6081 review.
var (
	// reSlug matches ids, keys, distros, package families, pool names.
	reSlug = regexp.MustCompile(`^[a-z0-9._-]+$`)
	// reDigits matches a bare integer (versionMajor).
	reDigits = regexp.MustCompile(`^[0-9]+$`)
	// reVersion is an injection-safe charset for any OS version string
	// (accepts "24.04", "stream", "2023", "8.x", "8.2024-04"): no whitespace,
	// quotes, shell/YAML metacharacters or newlines.
	reVersion = regexp.MustCompile(`^[a-zA-Z0-9.-]+$`)
	// reUbuntuVersion is the stricter shape required of Ubuntu versions, which
	// are interpolated into shell function names (is_ubuntu_<NN><NN>) and the
	// bundle Dockerfile FROM tag.
	reUbuntuVersion = regexp.MustCompile(`^[0-9]+\.[0-9]+$`)
	// reName allows human display names (letters, digits, spaces and a few
	// punctuation marks) but rejects newlines, quotes and shell/YAML specials.
	// It also validates a family's predicate description, which is rendered into
	// a shell comment line.
	reName = regexp.MustCompile(`^[a-zA-Z0-9 ._()-]+$`)
	// reURI is an injection-safe charset for cloud-image URLs.
	reURI = regexp.MustCompile(`^[a-zA-Z0-9:/._~%?=&+-]+$`)
	// rePredicate matches a shell function name (a family predicate such as
	// is_rhel_9_variant); it is both defined and called in generated shell.
	rePredicate = regexp.MustCompile(`^[a-z_][a-z0-9_]*$`)
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

	// Family names the distro family (see Matrix.Families) this OS belongs to.
	// A family renders one shared shell predicate (is_<name>) matched by LSB_DIST
	// and major version, rather than a per-version predicate. Membership is the
	// hook later convoy legs use to attach their family's per-OS capability data
	// to the shared model. Optional.
	Family string `yaml:"family,omitempty"`

	// Capability constraints. These drive computed preflight rules and the
	// capability-derived subset of testgrid unsupportedOSIDs.
	MinKubernetes       string `yaml:"minKubernetes,omitempty"`
	DockerSupported     *bool  `yaml:"dockerSupported,omitempty"`
	ApparmorWorkaround  bool   `yaml:"apparmorWorkaround,omitempty"`
	HostPackagesShipped bool   `yaml:"hostPackagesShipped,omitempty"`

	// BundleDockerfile selects OSes that get a generated parametrized k8s bundle
	// Dockerfile at bundles/k8s-ubuntu<versionMajor><versionMinor>/Dockerfile.
	BundleDockerfile bool `yaml:"bundleDockerfile,omitempty"`

	// PreflightName is the OS's display name in host-preflight `message` text
	// (e.g. "Ubuntu", "AmazonLinux"). The preflight `when` token is Distro.
	PreflightName string `yaml:"preflightName,omitempty"`
}

// Family is a distro family whose membership is defined by an LSB_DIST set and a
// set of major versions rather than by a single registry OS entry. It renders one
// shared shell predicate — is_<Predicate> — that hand-written installer code and
// the host_packages_shipped guard call. A family exists because its predicate must
// match machines kURL never testgrids (e.g. stock RHEL) and spans several distros
// and majors, so it cannot be derived from one OS row. OSes join via OS.Family;
// later convoy legs add their family's per-OS capability data on top of this model.
type Family struct {
	// Name is the family's registry key (referenced by OS.Family).
	Name string `yaml:"name"`
	// Predicate is the shell function name the family renders and callers use
	// (e.g. "is_rhel_9_variant").
	Predicate string `yaml:"predicate"`
	// Description completes the predicate's doc comment, verbatim:
	// "# <Predicate> returns 0 if the current distro is <Description>".
	Description string `yaml:"description"`
	// LSBDist is the set of $LSB_DIST tokens the predicate matches.
	LSBDist []string `yaml:"lsbDist"`
	// VersionMajors is the set of $DIST_VERSION_MAJOR values the predicate matches.
	VersionMajors []string `yaml:"versionMajors"`
	// HostPackagesShipped mirrors OS.HostPackagesShipped: true means this family
	// is handled by a dedicated/native package path, so it is EXCLUDED from the
	// generic host_packages_shipped detection (its predicate appears in that
	// guard's negated clause). RHEL-9-variant and Amazon-2023 use their own repos.
	HostPackagesShipped bool `yaml:"hostPackagesShipped"`
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
	Families []Family `yaml:"families"`
	OSes     []OS     `yaml:"oses"`
	Pools    []Pool   `yaml:"pools"`

	byKey    map[string]*OS
	byFamily map[string]*Family
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
	if err := m.validate(); err != nil {
		return nil, err
	}
	return &m, nil
}

// validate enforces the format (not just presence) of every scalar the
// generators interpolate, so a malformed or malicious registry edit fails
// generation loudly instead of producing corrupt or injected output.
func (m *Matrix) validate() error {
	for i := range m.OSes {
		o := &m.OSes[i]
		checks := []struct {
			name, val string
			re        *regexp.Regexp
			optional  bool
		}{
			{"id", o.ID, reSlug, false},
			{"key", o.Key, reSlug, true},
			{"distro", o.Distro, reSlug, true},
			{"packageFamily", o.PackageFamily, reSlug, true},
			{"versionMajor", o.VersionMajor, reDigits, true},
			{"minKubernetes", o.MinKubernetes, reVersion, true},
			{"version", o.Version, reVersion, false},
			{"name", o.Name, reName, false},
			{"vmimageuri", o.VMImageURI, reURI, false},
			{"preflightName", o.PreflightName, reName, true},
		}
		for _, c := range checks {
			if c.optional && c.val == "" {
				continue
			}
			if !c.re.MatchString(c.val) {
				return fmt.Errorf("os %q: field %s has invalid value %q (must match %s)", o.key(), c.name, c.val, c.re)
			}
		}
		// Ubuntu versions feed shell function names and the bundle Dockerfile
		// FROM tag, so they must be strictly numeric major.minor.
		if o.Distro == "ubuntu" && !reUbuntuVersion.MatchString(o.Version) {
			return fmt.Errorf("os %q: ubuntu version %q must match %s", o.key(), o.Version, reUbuntuVersion)
		}
		// A quoted preinit is rendered on one YAML line; a newline would break it.
		if o.PreinitStyle == PreinitQuoted && strings.Contains(o.Preinit, "\n") {
			return fmt.Errorf("os %q: quoted preinit must not contain a newline (use preinitStyle: block)", o.key())
		}
	}
	// Every OS with a Kubernetes floor must share the SAME floor: the generated
	// "Kubernetes Support" preflight encodes a single floor in its exclude
	// clause, so divergent floors would silently render wrong messages.
	floor := ""
	for i := range m.OSes {
		v := m.OSes[i].MinKubernetes
		if v == "" {
			continue
		}
		if floor == "" {
			floor = v
		} else if v != floor {
			return fmt.Errorf("divergent minKubernetes floors (%q vs %q); the generated preflight assumes a single floor", floor, v)
		}
	}
	// Families render shell predicate definitions and are called by name, so every
	// interpolated scalar must be constrained at the registry boundary.
	for i := range m.Families {
		f := &m.Families[i]
		if !reSlug.MatchString(f.Name) {
			return fmt.Errorf("family %q: name is not a safe slug (must match %s)", f.Name, reSlug)
		}
		if !rePredicate.MatchString(f.Predicate) {
			return fmt.Errorf("family %q: predicate %q is not a safe shell function name (must match %s)", f.Name, f.Predicate, rePredicate)
		}
		if !reName.MatchString(f.Description) {
			return fmt.Errorf("family %q: description %q has invalid value (must match %s)", f.Name, f.Description, reName)
		}
		if len(f.LSBDist) == 0 {
			return fmt.Errorf("family %q: lsbDist must list at least one distro token", f.Name)
		}
		for _, d := range f.LSBDist {
			if !reSlug.MatchString(d) {
				return fmt.Errorf("family %q: lsbDist token %q is not a safe slug (must match %s)", f.Name, d, reSlug)
			}
		}
		if len(f.VersionMajors) == 0 {
			return fmt.Errorf("family %q: versionMajors must list at least one major", f.Name)
		}
		for _, v := range f.VersionMajors {
			if !reDigits.MatchString(v) {
				return fmt.Errorf("family %q: versionMajor %q must be a bare integer (must match %s)", f.Name, v, reDigits)
			}
		}
	}
	// An OS's family tag must reference a declared family, and — when the OS
	// carries a major version — that major must be one the family matches, so a
	// mistagged OS fails loudly instead of silently escaping its predicate.
	for i := range m.OSes {
		o := &m.OSes[i]
		if o.Family == "" {
			continue
		}
		f, ok := m.byFamily[o.Family]
		if !ok {
			return fmt.Errorf("os %q: unknown family %q", o.key(), o.Family)
		}
		if o.VersionMajor != "" && !slices.Contains(f.VersionMajors, o.VersionMajor) {
			return fmt.Errorf("os %q: versionMajor %q is not in family %q majors %v", o.key(), o.VersionMajor, f.Name, f.VersionMajors)
		}
	}
	// Pool names become file paths (testgrid/specs/<name>.yaml); keep them slugs.
	for _, p := range m.Pools {
		if !reSlug.MatchString(p.Name) {
			return fmt.Errorf("pool name %q is not a safe slug (must match %s)", p.Name, reSlug)
		}
	}
	return nil
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
	m.byFamily = make(map[string]*Family, len(m.Families))
	for i := range m.Families {
		f := &m.Families[i]
		if f.Name == "" {
			return fmt.Errorf("family entry %d has empty name", i)
		}
		if _, dup := m.byFamily[f.Name]; dup {
			return fmt.Errorf("duplicate family name %q", f.Name)
		}
		m.byFamily[f.Name] = f
	}

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
