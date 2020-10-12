package runner

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_urlToPath(t *testing.T) {
	tests := []struct {
		name string
		url  string
		want string
	}{
		{
			name: "ubuntu-bionic",
			url:  "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img",
			want: "httpscloudimagesubuntucombioniccurrentbionicservercloudimgamd64img",
		},
		{
			name: "ubuntu-xenial",
			url:  "https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img",
			want: "httpscloudimagesubuntucomxenialcurrentxenialservercloudimgamd64disk1img",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := require.New(t)

			req.Equal(tt.want, urlToPath(tt.url))
		})
	}
}
