package scheduler

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_bundleFromURL(t *testing.T) {
	tests := []struct {
		name    string
		url     string
		want    string
		wantErr bool
	}{
		{
			name: "prod url",
			url:  "https://kurl.sh/01ceb6c",
			want: "https://kurl.sh/bundle/01ceb6c.tar.gz",
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

			got, err := bundleFromURL(tt.url)
			if tt.wantErr {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			req.Equal(tt.want, got)
		})
	}
}
