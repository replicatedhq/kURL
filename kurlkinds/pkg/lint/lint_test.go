package lint

import (
	"context"
	"embed"
	"path"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	"gopkg.in/yaml.v2"

	"github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

//go:embed regotests
var staticTests embed.FS

func TestValidate(t *testing.T) {
	type test struct {
		Name      string
		Installer v1beta1.Installer `yaml:"installer"`
		Output    []Output          `yaml:"output"`
	}

	entries, err := staticTests.ReadDir("regotests")
	if err != nil {
		t.Fatalf("unable to read test files: %s", err)
	}

	var tests []test
	for _, entry := range entries {
		fpath := path.Join("regotests", entry.Name())
		data, err := staticTests.ReadFile(fpath)
		if err != nil {
			t.Fatalf("unable to read test file %q: %s", fpath, err)
		}

		var onetest test
		if err := yaml.Unmarshal(data, &onetest); err != nil {
			t.Fatalf("invalid yaml on file %q: %s", fpath, err)
		}

		onetest.Name = fpath
		tests = append(tests, onetest)
	}

	for _, tt := range tests {
		t.Run(tt.Name, func(t *testing.T) {
			result, err := Validate(context.Background(), tt.Installer)
			if err != nil {
				t.Errorf("unexpected error returned: %s", err)
				return
			}

			less := func(a, b Output) bool { return a.Message < b.Message }
			diff := cmp.Diff(result, tt.Output, cmpopts.SortSlices(less))
			if diff != "" {
				t.Errorf("unexpected return: %s", diff)
			}
		})
	}
}

func TestVersions(t *testing.T) {
	vers, err := Versions(context.Background())
	if err != nil {
		t.Fatalf("unexpected error reading versions: %s", err)
	}

	// check some add-ons we need must be there, just assures we have indeed read and
	// parsed the rego data correctly.
	for _, addon := range []string{"kubernetes", "weave", "registry"} {
		if _, ok := vers[addon]; !ok {
			t.Fatalf("unable to find versions for %s", addon)
		}

		if len(vers[addon].Versions) == 0 {
			t.Fatalf("no versions found for %s", addon)
		}
	}

	// ensure latest is set and exists inside the add-on versions slice.
	for name, data := range vers {
		if data.Latest == "" {
			t.Fatalf("unset latest for %s", name)
		}

		var found bool
		for _, ver := range data.Versions {
			if ver != data.Latest {
				continue
			}

			found = true
			break
		}

		if !found {
			t.Fatalf("latest version not in the list of versions for %s", name)
		}
	}
}
