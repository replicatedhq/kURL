package clusterspace

import (
	"io"
	"log"
	"testing"

	"k8s.io/client-go/rest"
)

func Test_hasEnoughSpace(t *testing.T) {
	for _, tt := range []struct {
		name     string
		volume   OpenEBSVolume
		reserved int64
		hasSpace bool
		free     int64
	}{
		{
			name: "should pass with an empty open ebs volume",
		},
		{
			name:     "should pass when there is enough space (different mount point)",
			reserved: 99,
			free:     100,
			hasSpace: true,
			volume: OpenEBSVolume{
				Free:       100,
				Used:       0,
				RootVolume: false,
			},
		},
		{
			name:     "should pass when there is enough space (same mount point)",
			reserved: 50,
			free:     85,
			hasSpace: true,
			volume: OpenEBSVolume{
				Free:       100,
				Used:       0,
				RootVolume: true,
			},
		},
		{
			name:     "should not pass when there is not enough space (same mount point)",
			reserved: 86,
			free:     85,
			hasSpace: false,
			volume: OpenEBSVolume{
				Free:       100,
				Used:       0,
				RootVolume: true,
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			ochecker := OpenEBSDiskSpaceValidator{}
			free, hasSpace := ochecker.hasEnoughSpace(tt.volume, tt.reserved)

			if hasSpace != tt.hasSpace {
				t.Errorf("expected hasSpace to be %v, %v received instead", tt.hasSpace, hasSpace)
			}

			if free != tt.free {
				t.Errorf("expected free to be %v, %v received instead", tt.free, free)
			}
		})
	}
}

func TestNewOpenEBSChecker(t *testing.T) {
	// test empty logger
	_, err := NewOpenEBSDiskSpaceValidator(&rest.Config{}, nil, "image", "src", "dst")
	if err == nil || err.Error() != "no logger provided" {
		t.Errorf("expected failure creating object: %v", err)
	}

	logger := log.New(io.Discard, "", 0)

	// test empty image
	_, err = NewOpenEBSDiskSpaceValidator(&rest.Config{}, logger, "", "src", "dst")
	if err == nil || err.Error() != "empty image" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// test src storage class
	_, err = NewOpenEBSDiskSpaceValidator(&rest.Config{}, logger, "image", "", "dst")
	if err == nil || err.Error() != "empty source storage class" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// test empty dst sc
	_, err = NewOpenEBSDiskSpaceValidator(&rest.Config{}, logger, "image", "src", "")
	if err == nil || err.Error() != "empty destination storage class" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// happy path
	_, err = NewOpenEBSDiskSpaceValidator(&rest.Config{}, logger, "image", "src", "dst")
	if err != nil {
		t.Errorf("unexpected failure creating object: %v", err)
	}
}
