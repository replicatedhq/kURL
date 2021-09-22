package main

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_extractPreflightSpec(t *testing.T) {
	tests := []struct {
		name    string
		wantErr bool
	}{
		{
			name:    "basic",
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			err := extractPreflightSpec(fmt.Sprintf("testdata/%s/installer.yaml", tt.name), fmt.Sprintf("%s/%s/output.yaml", dir, tt.name))
			if tt.wantErr {
				require.NotNil(t, err)
				return
			}
		})
	}
}
