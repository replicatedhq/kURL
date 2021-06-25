package scheduler

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_getInstallerURL(t *testing.T) {
	tests := []struct {
		name        string
		url         string
		kurlVersion string
		want        string
		wantErr     bool
	}{
		{
			name: "prod url",
			url:  "https://kurl.sh/01ceb6c",
			want: "https://kurl.sh/01ceb6c",
		},
		{
			name:        "prod versioned url",
			url:         "https://kurl.sh/01ceb6c",
			want:        "https://kurl.sh/version/v2021.05.28-0/01ceb6c",
			kurlVersion: "v2021.05.28-0",
		},
		{
			name: "staging url",
			url:  "https://staging.kurl.sh/0441370",
			want: "https://staging.kurl.sh/0441370",
		},
		{
			name:    "broken url",
			url:     "hello world",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)

			got, err := getInstallerURL(tt.url, tt.kurlVersion)
			if tt.wantErr {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			req.Equal(tt.want, got)
		})
	}
}

func Test_getBundleFromURL(t *testing.T) {
	tests := []struct {
		name        string
		url         string
		kurlVersion string
		want        string
		wantErr     bool
	}{
		{
			name: "prod url",
			url:  "https://kurl.sh/01ceb6c",
			want: "https://kurl.sh/bundle/01ceb6c.tar.gz",
		},
		{
			name:        "prod versioned url",
			url:         "https://kurl.sh/01ceb6c",
			want:        "https://kurl.sh/bundle/version/v2021.05.28-0/01ceb6c.tar.gz",
			kurlVersion: "v2021.05.28-0",
		},
		{
			name: "staging url",
			url:  "https://staging.kurl.sh/0441370",
			want: "https://staging.kurl.sh/bundle/0441370.tar.gz",
		},
		{
			name:    "broken url",
			url:     "hello world",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)

			got, err := getBundleFromURL(tt.url, tt.kurlVersion)
			if tt.wantErr {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			req.Equal(tt.want, got)
		})
	}
}
