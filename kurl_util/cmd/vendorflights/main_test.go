package main

import (
	"fmt"
	"io/fs"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_extractPreflightSpec(t *testing.T) {
	tests := []struct {
		name             string
		preflightPresent bool
		wantErr          bool
	}{
		{
			name:             "basic",
			preflightPresent: true,
			wantErr:          false,
		},
		{
			name:             "missing-preflight",
			preflightPresent: false,
			wantErr:          false,
		},
		{
			name:             "v1beta1",
			preflightPresent: false,
			wantErr:          true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			err := extractPreflightSpec(fmt.Sprintf("testdata/%s/installer.yaml", tt.name), fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
			require.Equal(t, tt.wantErr, err != nil)
			if tt.preflightPresent {
				expected, err := os.ReadFile(fmt.Sprintf("testdata/%s/expected_preflights.yaml", tt.name))
				require.NoError(t, err)
				actual, err := os.ReadFile(fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
				require.NoError(t, err)
				require.Equal(t, string(expected), string(actual))
				return
			}
			_, err = os.Stat(fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
			require.ErrorIs(t, err, fs.ErrNotExist)

		})
	}
}
