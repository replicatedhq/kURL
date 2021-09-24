package main

import (
	"errors"
	"fmt"
	"io/fs"
	"io/ioutil"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_extractPreflightSpec(t *testing.T) {
	tests := []struct {
		name             string
		preflightPresent bool
	}{
		{
			name:             "basic",
			preflightPresent: true,
		},
		{
			name:             "missing-preflight",
			preflightPresent: false,
		},
		{
			name:             "v1beta1",
			preflightPresent: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			err := extractPreflightSpec(fmt.Sprintf("testdata/%s/installer.yaml", tt.name), fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
			require.Nil(t, err)
			if tt.preflightPresent {
				expected, err := ioutil.ReadFile(fmt.Sprintf("testdata/%s/expected_preflights.yaml", tt.name))
				require.Nil(t, err)
				actual, err := ioutil.ReadFile(fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
				require.Nil(t, err)
				require.Equal(t, string(expected), string(actual))
				return
			}
			_, err = os.Stat(fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
			require.True(t, errors.Is(err, fs.ErrNotExist))

		})
	}
}
