package main

import (
	_ "embed"
	"testing"

	"github.com/stretchr/testify/require"
)

//go:embed testfiles/latest.yaml
var latestYaml string

//go:embed testfiles/complex.yaml
var complexYaml string

func Test_jsonField(t *testing.T) {
	tests := []struct {
		name     string
		filePath string
		jsonPath string
		want     string
		wantErr  bool
	}{
		{
			name:     "specific addon from latest",
			filePath: "latest",
			jsonPath: "spec.weave",
			want:     `{"version":"latest"}`,
		},
		{
			name:     "addon that does not exist from latest",
			filePath: "latest",
			jsonPath: "spec.longhorn",
			want:     ``,
			wantErr:  true,
		},
		{
			name:     "multiline strings and quotes",
			filePath: "complex",
			jsonPath: "spec.docker",
			want:     `{"daemonConfig":"this is a test file with newlines\nand quotes\"\nwithin it\n","version":"20.10.5"}`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)
			testReader := func(path string) []byte {
				if path == "latest" {
					return []byte(latestYaml)
				}
				if path == "complex" {
					return []byte(complexYaml)
				}
				return nil
			}
			got, err := jsonField(testReader, tt.filePath, tt.jsonPath)
			req.Equal(tt.want, got)
			if tt.wantErr {
				req.Error(err)
			} else {
				req.NoError(err)
			}
		})
	}
}
