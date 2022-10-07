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
	"bytes"
	"context"
	"embed"
	"fmt"
	"net/url"
	"path"

	"github.com/mitchellh/mapstructure"
	"github.com/open-policy-agent/opa/rego"

	"github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

//go:embed rego
var static embed.FS

// Output holds the outcome of a lint pass on top of a Installer struct.
type Output struct {
	Field   string `json:"field,omitempty"`
	Type    string `json:"type,omitempty"`
	Message string `json:"message,omitempty"`
}

// AddOn holds an add-on and its respective supported versions.
type AddOn struct {
	Latest   string   `json:"latest"`
	Versions []string `json:"versions"`
}

type Linter struct {
	staticVersions map[string]AddOn
	apiBaseURL     *url.URL
}

// New returns a new v1beta1.Installer linter. this linter is capable of evaluating if a
// struct has all its fields properly set, rules in the "rego/" directory are used.
func New(opts ...Option) *Linter {
	linter := &Linter{}
	for _, opt := range opts {
		opt(linter)
	}
	return linter
}

// Versions return a map containing all supported versions indexed by add-on name. it
// goes and fetch the versions from a remote endpoint.
func (l *Linter) Versions(ctx context.Context, inst v1beta1.Installer) (map[string]AddOn, error) {
	if l.staticVersions != nil {
		return l.staticVersions, nil
	}

	content, err := l.replaceAPIBaseURL(ctx)
	if err != nil {
		return nil, fmt.Errorf("error preparing for api requests: %w", err)
	}

	rules := rego.New(
		rego.Query("data.kurl.installer.known_versions"),
		rego.Module("rego/variables.rego", string(content)),
		rego.Input(inst),
	)

	rs, err := rules.Eval(ctx)
	if err != nil {
		return nil, fmt.Errorf("unexpected error getting add-on versions: %w", err)
	}

	if len(rs) == 0 || len(rs[0].Expressions) == 0 {
		return nil, fmt.Errorf("unexpected empty rego eval return")
	}

	result := map[string]AddOn{}
	if err := mapstructure.Decode(rs[0].Expressions[0].Value, &result); err != nil {
		return nil, fmt.Errorf("error decoding result: %w", err)
	}

	if len(result) == 0 {
		return nil, fmt.Errorf("unable to get versions from %s", l.apiBaseURL.String())
	}

	return result, nil
}

// Validate checks the provided Installer for errors.
func (l *Linter) Validate(ctx context.Context, inst v1beta1.Installer) ([]Output, error) {
	content, err := l.replaceAPIBaseURL(ctx)
	if err != nil {
		return nil, fmt.Errorf("error preparing for api requests: %w", err)
	}

	options := []func(*rego.Rego){
		rego.Query("data.kurl.installer.lint"),
		rego.Module("rego/variables.rego", string(content)),
		rego.Input(inst),
	}

	for _, fname := range []string{"functions.rego", "output.rego"} {
		fpath := path.Join("rego", fname)
		content, err := static.ReadFile(fpath)
		if err != nil {
			return nil, fmt.Errorf("unable to load rego rules: %w", err)
		}
		options = append(options, rego.Module(fname, string(content)))
	}

	rs, err := rego.New(options...).Eval(ctx)
	if err != nil {
		return nil, fmt.Errorf("unexpected error evaluating installer: %w", err)
	}

	if len(rs) == 0 || len(rs[0].Expressions) == 0 {
		return []Output{}, nil
	}

	result := []Output{}
	if err := mapstructure.Decode(rs[0].Expressions[0].Value, &result); err != nil {
		return nil, fmt.Errorf("error decoding result: %w", err)
	}

	for _, res := range result {
		if res.Type == "preprocess" {
			err := fmt.Errorf(res.Message)
			return nil, fmt.Errorf("error processing rules: %w", err)
		}
	}

	return result, nil
}

// replaceAPIBaseURL replaces the api base url used for querying add-on versions. this is
// https://kurl.sh by default but can be replaced (for sake of testing or running against
// our staging environment).
func (l *Linter) replaceAPIBaseURL(ctx context.Context) ([]byte, error) {
	content, err := static.ReadFile("rego/variables.rego")
	if err != nil {
		return nil, fmt.Errorf("error reading rego variables file: %w", err)
	}

	if l.apiBaseURL == nil {
		return content, nil
	}
	// if the version url has been set by the user we replace it here.
	oldurl := []byte("https://kurl.sh")
	newurl := []byte(l.apiBaseURL.String())
	content = bytes.ReplaceAll(content, oldurl, newurl)
	return content, nil
}
