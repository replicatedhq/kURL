/*
Copyright 2022 Replicated Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package lint

import (
	"context"
	"embed"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path"
	"reflect"
	"strings"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	"gopkg.in/yaml.v2"

	"github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

//go:embed regotests
var staticTests embed.FS

func TestStaticVersions(t *testing.T) {
	static := map[string]AddOn{
		"addon0": {
			Latest: "1.0.0",
			Versions: []string{
				"1.0.0",
				"2.0.0",
				"3.0.0",
			},
		},
	}

	var empty v1beta1.Installer
	linter := New(WithStaticVersions(static))
	res, err := linter.Versions(context.Background(), empty)
	if err != nil {
		t.Fatalf("unexpected error: %s", err)
	}

	if !reflect.DeepEqual(res, static) {
		t.Errorf("expecting %+v, received %+v", static, res)
	}
}

func TestValidateWithInvalidURL(t *testing.T) {
	u, err := url.Parse("https://i.do.not.exist")
	if err != nil {
		t.Fatalf("unable to parse test url: %s", err)
	}

	installer := v1beta1.Installer{
		Spec: v1beta1.InstallerSpec{
			Kubernetes: &v1beta1.Kubernetes{
				Version: "latest",
			},
			Containerd: &v1beta1.Containerd{
				Version: "latest",
			},
		},
	}

	linter := New(WithAPIBaseURL(u))
	if _, err = linter.Validate(context.Background(), installer); err == nil {
		t.Error("expecting error, nil received instead")
		return
	}

	if !strings.Contains(err.Error(), "i.do.not.exist: no such host") {
		t.Errorf("unexpected error: %s", err)
	}
}

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
		// this file is used in our mock kurl api endpoint, just ignore it.
		if entry.Name() == "versions.json" {
			continue
		}

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

	apires, err := staticTests.ReadFile("regotests/versions.json")
	if err != nil {
		t.Fatalf("unable to read mock webserver result: %s", err)
	}

	mocksrv := httptest.NewServer(
		http.HandlerFunc(
			func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("content-type", "application/json")
				w.Write(apires)
			},
		),
	)
	defer mocksrv.Close()

	mockurl, err := url.Parse(mocksrv.URL)
	if err != nil {
		t.Fatalf("unable to parse mock server url: %s", err)
	}

	linter := New(WithAPIBaseURL(mockurl))
	for _, tt := range tests {
		t.Run(tt.Name, func(t *testing.T) {
			result, err := linter.Validate(context.Background(), tt.Installer)
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

func TestVersionsWithInvalidURL(t *testing.T) {
	u, err := url.Parse("https://i.do.not.exist")
	if err != nil {
		t.Fatalf("unable to parse URL: %s", err)
	}

	var empty v1beta1.Installer
	linter := New(WithAPIBaseURL(u))
	if _, err = linter.Versions(context.Background(), empty); err == nil {
		t.Fatal("expecting error but nil received instead")
	}
}

func TestCustomAPIEndpoint(t *testing.T) {
	httpAnswer := map[string][]string{
		"addon0": {"latest", "3.0.0", "2.0.0", "1.0.0"},
		"addon1": {"8.0.0", "7.0.0", "latest", "6.0.0"},
	}

	expected := map[string]AddOn{
		"addon0": {
			Latest:   "3.0.0",
			Versions: []string{"3.0.0", "2.0.0", "1.0.0"},
		},
		"addon1": {
			Latest:   "6.0.0",
			Versions: []string{"8.0.0", "7.0.0", "6.0.0"},
		},
	}

	srv := httptest.NewServer(
		http.HandlerFunc(
			func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/installer" {
					t.Fatalf("wrong url path: %s", r.URL.Path)
				}

				w.Header().Set("content-type", "application/json")
				if err := json.NewEncoder(w).Encode(httpAnswer); err != nil {
					t.Fatalf("error encoding http server return: %s", err)
				}
			},
		),
	)
	defer srv.Close()

	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("error parsing http test server url: %s", err)
	}

	var empty v1beta1.Installer
	result, err := New(WithAPIBaseURL(u)).Versions(context.Background(), empty)
	if err != nil {
		t.Fatalf("unable to get versions from custom api endpoint: %s", err)
	}

	if !reflect.DeepEqual(result, expected) {
		t.Errorf("expected %+v, received %+v", expected, result)
	}
}

func TestKurlVersionSet(t *testing.T) {
	httpAnswer := map[string][]string{
		"kubernetes": {"latest", "6.6.6"},
		"containerd": {"latest", "5.5.5"},
	}

	srv := httptest.NewServer(
		http.HandlerFunc(
			func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/installer/version/v1879.03.14" {
					t.Fatalf("wrong url path: %s", r.URL.Path)
				}

				w.Header().Set("content-type", "application/json")
				if err := json.NewEncoder(w).Encode(httpAnswer); err != nil {
					t.Fatalf("error encoding http server return: %s", err)
				}
			},
		),
	)
	defer srv.Close()

	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("error parsing http test server url: %s", err)
	}

	installer := v1beta1.Installer{
		Spec: v1beta1.InstallerSpec{
			Kubernetes: &v1beta1.Kubernetes{
				Version: "6.6.6",
			},
			Containerd: &v1beta1.Containerd{
				Version: "5.5.5",
			},
			Kurl: &v1beta1.Kurl{
				InstallerVersion: "v1879.03.14",
			},
		},
	}

	linter := New(WithAPIBaseURL(u))
	if _, err := linter.Validate(context.Background(), installer); err != nil {
		t.Fatalf("unable to get versions from custom api endpoint: %s", err)
	}
}

func TestVersions(t *testing.T) {
	var empty v1beta1.Installer
	vers, err := New().Versions(context.Background(), empty)
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
