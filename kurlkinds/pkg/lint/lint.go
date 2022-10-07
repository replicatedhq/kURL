/*
Copyright 2020 Replicated Inc.

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
	"fmt"
	"path"
	"sync"

	"github.com/open-policy-agent/opa/rego"

	"github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

var (
	//go:embed rego
	static   embed.FS
	versions map[string]AddOn
	mtx      sync.Mutex
)

// Output holds the outcome of a lint pass on top of a Installer struct.
type Output struct {
	Field   string `json:"field,omitempty"`
	Message string `json:"message,omitempty"`
}

// AddOn holds an add-on and its respective supported versions.
type AddOn struct {
	Latest   string   `json:"latest"`
	Versions []string `json:"versions"`
}

// Versions return a map containing all supported versions indexed by add-on name. this
// functions parses the content of "rego/vars.rego" and reads a policy called known_versions.
// reading and parsing "rego/vars.rego" file is executed only once.
func Versions(ctx context.Context) (map[string]AddOn, error) {
	mtx.Lock()
	defer mtx.Unlock()

	if versions != nil {
		return versions, nil
	}

	content, err := static.ReadFile("rego/vars.rego")
	if err != nil {
		return nil, fmt.Errorf("error reading rego variables file: %w", err)
	}

	vars := rego.New(
		rego.Query("data.kurl.installer.known_versions"),
		rego.Module("rego/vars.rego", string(content)),
	)

	rs, err := vars.Eval(ctx)
	if err != nil {
		return nil, fmt.Errorf("unexpected error getting add-on versions: %w", err)
	}

	if len(rs) == 0 || len(rs[0].Expressions) == 0 {
		return nil, fmt.Errorf("unexpected empty rego eval return")
	}

	dt, err := json.Marshal(rs[0].Expressions[0].Value)
	if err != nil {
		return nil, fmt.Errorf("unable to marshal rego variables: %w", err)
	}

	result := map[string]AddOn{}
	if err := json.Unmarshal(dt, &result); err != nil {
		return nil, fmt.Errorf("unable to unmarshal rego variables: %w", err)
	}

	versions = result
	return versions, nil
}

// Validate checks the provided Installer for errors.
func Validate(ctx context.Context, installer v1beta1.Installer) ([]Output, error) {
	options := []func(*rego.Rego){
		rego.Query("data.kurl.installer.lint"),
		rego.Input(installer),
	}

	for _, fname := range []string{"rules.rego", "vars.rego", "errors.rego"} {
		fpath := path.Join("rego", fname)
		content, err := static.ReadFile(fpath)
		if err != nil {
			return nil, fmt.Errorf("unable to load rego rules: %w", err)
		}

		contentstr := string(content)
		options = append(options, rego.Module(fname, contentstr))
	}

	rules := rego.New(options...)
	rs, err := rules.Eval(ctx)
	if err != nil {
		return nil, fmt.Errorf("unexpected error evaluating installer: %w", err)
	}

	if len(rs) == 0 {
		return []Output{}, nil
	}

	result := []Output{}
	for _, rsref := range rs {
		for _, exp := range rsref.Expressions {
			values, ok := exp.Value.([]interface{})
			if !ok {
				return nil, fmt.Errorf("unexpected value type: %T", exp.Value)
			}

			for _, val := range values {
				dt, err := json.Marshal(val)
				if err != nil {
					return nil, fmt.Errorf("error marshaling result :%w", err)
				}

				var out Output
				if err := json.Unmarshal(dt, &out); err != nil {
					return nil, fmt.Errorf("error unmarshaling result: %w", err)
				}

				result = append(result, out)
			}
		}
	}

	return result, nil
}
