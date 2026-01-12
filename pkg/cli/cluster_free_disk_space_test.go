package cli

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/google/go-cmp/cmp"
	storagev1 "k8s.io/api/storage/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
)

func Test_getStorageClassByName(t *testing.T) {
	for _, tt := range []struct {
		name   string
		scname string
		objs   []runtime.Object
		err    string
		exp    runtime.Object
	}{
		{
			name: "returns error if default storage class was not found",
			err:  "failed to find the default storage class",
		},
		{
			name:   "returns error if provided storage class was not found",
			scname: "does-not-exist",
			err:    "failed to find storage class",
		},
		{
			name: "returns the default storage class if no name has been provided",
			err:  "",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "this-is-not-the-default",
						Annotations: map[string]string{
							isDefaultStorageClassAnnotation: "false",
						},
					},
				},
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "this-is-the-default",
						Annotations: map[string]string{
							isDefaultStorageClassAnnotation: "true",
						},
					},
				},
			},
			exp: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "this-is-the-default",
					Annotations: map[string]string{
						isDefaultStorageClassAnnotation: "true",
					},
				},
			},
		},
		{
			name:   "returns the class by its name",
			err:    "",
			scname: "the-expected-class",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "this-is-not-the-default",
						Annotations: map[string]string{
							isDefaultStorageClassAnnotation: "false",
						},
					},
				},
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "this-is-the-default",
						Annotations: map[string]string{
							isDefaultStorageClassAnnotation: "true",
						},
					},
				},
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "the-expected-class",
					},
				},
			},
			exp: &storagev1.StorageClass{
				ObjectMeta: metav1.ObjectMeta{
					Name: "the-expected-class",
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			cli := fake.NewClientset(tt.objs...)
			sc, err := getStorageClassByName(context.Background(), cli, tt.scname)
			if err != nil {
				if len(tt.err) == 0 {
					t.Errorf("unexpected error: %s", err)
				} else if !strings.Contains(err.Error(), tt.err) {
					t.Errorf("expecting %q, %q received instead", tt.err, err)
				}
				return
			}

			if len(tt.err) > 0 {
				t.Errorf("expecting error %q, nil received instead", tt.err)
			}

			if diff := cmp.Diff(tt.exp, sc); diff != "" {
				t.Errorf("unexpected return: %s", diff)
			}
		})
	}
}

func Test_hasEnoughSpace(t *testing.T) {
	for _, tt := range []struct {
		name       string
		nodeName   string
		free       int64
		biggerThan int64
		msg        string
		exp        bool
	}{
		{
			name:       "returns true if it has space",
			nodeName:   "node0",
			free:       1000,
			biggerThan: 999,
			msg:        "Node node0 has 1000B available",
			exp:        true,
		},
		{
			name:       "returns false if it has no space",
			nodeName:   "node1",
			free:       999,
			biggerThan: 1000,
			msg:        "Not enough space on node node1 (requested 1000B, available 999B)",
			exp:        false,
		},
		{
			name:       "returns true if it free space is equal to requested space",
			nodeName:   "node2",
			free:       1000,
			biggerThan: 1000,
			msg:        "Node node2 has 1000B available",
			exp:        true,
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			out, ok := hasEnoughSpace(tt.nodeName, tt.free, tt.biggerThan)
			if ok != tt.exp {
				t.Errorf("expected %v, received %v", tt.exp, ok)
			}
			fmt.Println(out)
			if !strings.Contains(out, tt.msg) {
				t.Errorf("expecting %s, %s received instead", tt.msg, out)
			}

		})
	}
}
