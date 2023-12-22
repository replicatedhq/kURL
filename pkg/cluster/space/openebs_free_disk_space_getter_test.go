package clusterspace

import (
	"context"
	"io"
	"log"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/go-cmp/cmp"
	corev1 "k8s.io/api/core/v1"
	storagev1 "k8s.io/api/storage/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/fake"
	"k8s.io/utils/ptr"
)

func Test_deleteTmpPVCs(t *testing.T) {
	for _, tt := range []struct {
		name    string
		objs    []runtime.Object
		timeout time.Duration
		pvcs    []*corev1.PersistentVolumeClaim
		err     string
		gofn    func(*testing.T, kubernetes.Interface)
	}{
		{
			name:    "deleting empty list of pvcs should succeed",
			timeout: time.Second,
		},
		{
			name:    "deleting non existing pvcs should succeed",
			timeout: time.Second,
			pvcs: []*corev1.PersistentVolumeClaim{
				{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "i-do-not-exist",
						Namespace: "default",
					},
				},
			},
		},
		{
			name:    "a pv with nil claim ref should not cause it to crash",
			timeout: time.Second,
			objs: []runtime.Object{
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "pv",
					},
				},
			},
			pvcs: []*corev1.PersistentVolumeClaim{
				{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
			},
		},
		{
			name:    "a pv referring to a different pvc should not crash",
			timeout: time.Second,
			objs: []runtime.Object{
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "pv",
					},
					Spec: corev1.PersistentVolumeSpec{
						ClaimRef: &corev1.ObjectReference{
							Name:      "abc",
							Namespace: "default",
						},
					},
				},
			},
			pvcs: []*corev1.PersistentVolumeClaim{
				{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
			},
		},
		{
			name:    "pv disappear after a while should succeed",
			timeout: 20 * time.Second,
			objs: []runtime.Object{
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "pv",
					},
					Spec: corev1.PersistentVolumeSpec{
						ClaimRef: &corev1.ObjectReference{
							Name:      "pvc",
							Namespace: "default",
						},
					},
				},
			},
			pvcs: []*corev1.PersistentVolumeClaim{
				{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
			},
			gofn: func(t *testing.T, kcli kubernetes.Interface) {
				time.Sleep(6 * time.Second)
				if err := kcli.CoreV1().PersistentVolumes().Delete(
					context.Background(), "pv", metav1.DeleteOptions{},
				); err != nil {
					t.Errorf("failed to delete test pv: %s", err)
				}
			},
		},
		{
			name:    "pv not disappearing should timeout",
			timeout: 10 * time.Second,
			err:     "timeout",
			objs: []runtime.Object{
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "pv",
					},
					Spec: corev1.PersistentVolumeSpec{
						ClaimRef: &corev1.ObjectReference{
							Name:      "pvc",
							Namespace: "default",
						},
					},
				},
			},
			pvcs: []*corev1.PersistentVolumeClaim{
				{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
			},
		},
		{
			name:    "pvs referring to pvcs from different namespaces should not interfere",
			timeout: 20 * time.Second,
			objs: []runtime.Object{
				&corev1.PersistentVolumeClaim{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "pv",
					},
					Spec: corev1.PersistentVolumeSpec{
						ClaimRef: &corev1.ObjectReference{
							Name:      "pvc",
							Namespace: "default",
						},
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "another-pv",
					},
					Spec: corev1.PersistentVolumeSpec{
						ClaimRef: &corev1.ObjectReference{
							Name:      "pvc",
							Namespace: "different-namespace",
						},
					},
				},
				&corev1.PersistentVolume{
					ObjectMeta: metav1.ObjectMeta{
						Name: "yet-another-pv",
					},
					Spec: corev1.PersistentVolumeSpec{
						ClaimRef: &corev1.ObjectReference{
							Name:      "pvc",
							Namespace: "yet-another-different-namespace",
						},
					},
				},
			},
			pvcs: []*corev1.PersistentVolumeClaim{
				{
					ObjectMeta: metav1.ObjectMeta{
						Name:      "pvc",
						Namespace: "default",
					},
				},
			},
			gofn: func(t *testing.T, kcli kubernetes.Interface) {
				time.Sleep(6 * time.Second)
				if err := kcli.CoreV1().PersistentVolumes().Delete(
					context.Background(), "pv", metav1.DeleteOptions{},
				); err != nil {
					t.Errorf("failed to delete test pv: %s", err)
				}
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			logger := log.New(io.Discard, "", 0)
			kcli := fake.NewSimpleClientset(tt.objs...)
			ochecker := OpenEBSFreeDiskSpaceGetter{
				deletePVTimeout: tt.timeout,
				kcli:            kcli,
				log:             logger,
			}

			if tt.gofn != nil {
				go tt.gofn(t, kcli)
			}

			err := ochecker.deleteTmpPVCs(tt.pvcs)
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
		})
	}
}

func Test_nodeIsScheduleable(t *testing.T) {
	for _, tt := range []struct {
		name        string
		err         bool
		annotations map[string]string
	}{
		{
			name: "should fail when node is not ready",
			err:  true,
			annotations: map[string]string{
				"node.kubernetes.io/not-ready": "NoExecute",
			},
		},
		{
			name: "should failed when node has multiple not ready annotations",
			err:  true,
			annotations: map[string]string{
				"node.kubernetes.io/not-ready":              "NoExecute",
				"node.cloudprovider.kubernetes.io/shutdown": "NoExecute",
				"node.kubernetes.io/unschedulable":          "NoExecute",
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			node := corev1.Node{
				ObjectMeta: metav1.ObjectMeta{
					Annotations: tt.annotations,
				},
			}

			ochecker := OpenEBSFreeDiskSpaceGetter{}
			err := ochecker.nodeIsSchedulable(node)
			if err != nil {
				if !tt.err {
					t.Errorf("unexpected error: %s", err)
				}
				return
			}

			if tt.err {
				t.Errorf("expecting error nil received instead")
			}
		})
	}
}

func Test_bulidTmpPVC(t *testing.T) {
	for _, tt := range []struct {
		name         string
		nodeName     string
		scname       string
		expectedName string
		expectedSpec corev1.PersistentVolumeClaimSpec
	}{
		{
			name:         "should pass with the full node name",
			nodeName:     "node0",
			expectedName: "disk-free-node0-",
			scname:       "xyz",
			expectedSpec: corev1.PersistentVolumeClaimSpec{
				StorageClassName: ptr.To("xyz"),
				AccessModes:      []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
				Resources: corev1.VolumeResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceStorage: resource.MustParse("1Mi"),
					},
				},
			},
		},
		{
			name:         "should trim pvc name if longer than 63 chars",
			nodeName:     "this-is-a-relly-long-host-name-and-this-should-be-trimmed",
			expectedName: "disk-free-this-is-a-relly-long-and-this-should-be-trimmed-",
			scname:       "default",
			expectedSpec: corev1.PersistentVolumeClaimSpec{
				StorageClassName: ptr.To("default"),
				AccessModes:      []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
				Resources: corev1.VolumeResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceStorage: resource.MustParse("1Mi"),
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			ochecker := OpenEBSFreeDiskSpaceGetter{
				scname: tt.scname,
			}
			pvc := ochecker.buildTmpPVC(tt.nodeName)

			if !strings.HasPrefix(pvc.Name, tt.expectedName) {
				t.Errorf("expected name to have prefix %s, %s received", tt.expectedName, pvc.Name)
			}

			if diff := cmp.Diff(tt.expectedSpec, pvc.Spec); diff != "" {
				t.Errorf("unexpected return: %s", diff)
			}
		})
	}
}

func Test_parseDFContainerOutput(t *testing.T) {
	for _, tt := range []struct {
		name         string
		content      []byte
		err          string
		expectedFree int64
		expectedUsed int64
	}{
		{
			name:    "should fail with empty df result",
			content: []byte(``),
			err:     "failed to locate free space info in pod log",
		},
		{
			name:    "should faile with invalid df return",
			content: []byte(`...---...---...<<<<>>>>>>`),
			err:     "failed to locate free space info in pod log",
		},
		{
			name: "should fail if df returns human readable format",
			content: []byte(`Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2        59G   49G  6.9G  88% /data`),
			err: `failed to parse "6.9G" as available spac`,
		},
		{
			name: "should fail if df returns human readable format (used)",
			content: []byte(`Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2        59G   49G  100  88% /data`),
			err: `failed to parse "49G" as used spac`,
		},
		{
			name: "should fail if df return does not contain /data mount point",
			content: []byte(`Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2        59G   49G  6.9G  88% /`),
			err: "failed to locate free space info in pod log",
		},
		{
			name:    "should fail if the line ends with /data but the content is invalid",
			content: []byte(`something weird /data`),
			err:     "failed to locate free space info in pod log",
		},
		{
			name:    "should fail if df result ends with /data but we can't parse the values",
			content: []byte(`this is a failure /data`),
			err:     `failed to parse "a" as available space`,
		},
		{
			name: "should succeed to parse df command output",
			content: []byte(`Filesystem       1B-blocks        Used  Available Use% Mounted on
/dev/sda2      63087357952 52521754624 7327760384  88% /data`),
			expectedFree: 7327760384,
			expectedUsed: 52521754624,
		},
		{
			name: "should pass even with an empty line among the df result",
			content: []byte(`Filesystem       1B-blocks        Used  Available Use% Mounted on

/dev/sda2      63087357952 52521754624 7327760384  88% /data`),
			expectedFree: 7327760384,
			expectedUsed: 52521754624,
		},
		{
			name: "should pass regardless of the number of prefixes in the df result",
			content: []byte(`Filesystem       1B-blocks        Used  Available Use% Mounted on
some prefixes go in here /dev/sda2      63087357952 52521754624 7327760384  88% /data`),
			expectedFree: 7327760384,
			expectedUsed: 52521754624,
		},
		{
			name: "should be able to parse df result (oracle linux output)",
			content: []byte(`Filesystem       1B-blocks       Used   Available Use% Mounted on
/dev/xvda1     85886742528 8500056064 77386686464  10% /data`),
			expectedFree: 77386686464,
			expectedUsed: 8500056064,
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			ochecker := OpenEBSFreeDiskSpaceGetter{}
			free, used, err := ochecker.parseDFContainerOutput(tt.content)
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

			if !reflect.DeepEqual(tt.expectedFree, free) {
				t.Errorf("expected free %v, received %v", tt.expectedFree, free)
			}
			if !reflect.DeepEqual(tt.expectedUsed, used) {
				t.Errorf("expected used %v, received %v", tt.expectedUsed, used)
			}
		})
	}
}

func Test_parseFstabContainerOutput(t *testing.T) {
	for _, tt := range []struct {
		name     string
		content  []byte
		err      string
		expected []string
	}{
		{
			name: "should be able to parse oracle linux amazon example fstab",
			content: []byte(`#
UUID=d8605abb-d6cd-4a46-a657-b6bd206da2ab     /           xfs    defaults,noatime  1   1`),
			expected: []string{"/"},
		},
		{
			name: "should be able to parse ubuntu 22.04 example fstab",
			content: []byte(`# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/sda2 during curtin installation
/dev/disk/by-uuid/ba03d262-e4fc-4bb2-8e2f-4e654315da3a / ext4 defaults 0 1`),
			expected: []string{"/"},
		},
		{
			name: "should pass with multiple mount points in the fstab",
			content: []byte(`# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/sda2 during curtin installation
/dev/disk/by-uuid/ba03d262-e4fc-4bb2-8e2f-4e654315da3a / ext4 defaults 0 1
/dev/disk/by-uuid/4bb2-8e2f-4e654315da3a /opt ext4 defaults 0 1`),
			expected: []string{"/", "/opt"},
		},
		{
			name:    "should fail if fstab is empty",
			content: []byte(``),
			err:     "failed to locate any mount point",
		},
		{
			name: "should pass if fstab contains uuid and with none",
			content: []byte(`# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>

proc  /proc  proc  defaults  0  0
# /dev/sda5
UUID=be35a709-c787-4198-a903-d5fdc80ab2f8  /  ext3  relatime,errors=remount-ro  0  1
# /dev/sda6
UUID=cee15eca-5b2e-48ad-9735-eae5ac14bc90  none  swap  sw  0  0

/dev/scd0  /media/cdrom0  udf,iso9660  user,noauto,exec,utf8  0  0`),
			expected: []string{"/proc", "/", "/media/cdrom0"},
		},
		{
			name: "should dedup repeated mount point",
			content: []byte(`# FAT ~ Linux calls FAT file systems vfat)
# /dev/hda1
UUID=12102C02102CEB83  /media/windows  vfat auto,users,uid=1000,gid=100,dmask=027,fmask=137,utf8  0  0

# NTFS ~ Use ntfs-3g for write access (rw) 
# /dev/hda1
UUID=12102C02102CEB83  /media/windows  ntfs-3g  auto,users,uid=1000,gid=100,dmask=027,fmask=137,utf8  0  0

# Zip Drives ~ Linux recognizes ZIP drives as sdx'''4'''

# Separate Home
# /dev/sda7
UUID=413eee0c-61ff-4cb7-a299-89d12b075093  /home  ext3  nodev,nosuid,relatime  0  2

# Data partition
# /dev/sda8
UUID=3f8c5321-7181-40b3-a867-9c04a6cd5f2f  /media/data  ext3  relatime,noexec  0  2

# Samba
//server/share  /media/samba  cifs  user=user,uid=1000,gid=100  0  0
# "Server" = Samba server (by IP or name if you have an entry for the server in your hosts file
# "share" = name of the shared directory
# "user" = your samba user
# This set up will ask for a password when mounting the samba share. If you do not want to enter a password, use a credentials file.
# replace "user=user" with "credentials=/etc/samba/credentials" In the credentials file put two lines
# username=user
# password=password
# make the file owned by root and ro by root (sudo chown root.root /etc/samba/credentials && sudo chmod 400 /etc/samba/credentials)

# NFS
Server:/share  /media/nfs  nfs  rsize=8192 and wsize=8192,noexec,nosuid
# "Server" = Samba server (by IP or name if you have an entry for the server in your hosts file
# "share" = name of the shared directory

#SSHFS
sshfs#user@server:/share  fuse  user,allow_other  0  0
# "Server" = Samba server (by IP or name if you have an entry for the server in your hosts file
# "share" = name of the shared directory`),
			expected: []string{"/media/windows", "/home", "/media/data", "/media/samba", "/media/nfs"},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			ochecker := OpenEBSFreeDiskSpaceGetter{}
			output, err := ochecker.parseFstabContainerOutput(tt.content)
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

			if !reflect.DeepEqual(tt.expected, output) {
				t.Errorf("expected %v, received %v", tt.expected, output)
			}
		})
	}
}

func Test_basePath(t *testing.T) {
	for _, tt := range []struct {
		name     string
		expected string
		err      string
		scname   string
		objs     []runtime.Object
	}{
		{
			name:   "should fail if can't get the storage class",
			scname: "does-not-exist",
			err:    `class: storageclasses.storage.k8s.io "does-not-exist" not found`,
			objs:   []runtime.Object{},
		},
		{
			name:   "no annotation",
			scname: "default",
			err:    "annotation not found in storage class",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
					},
				},
			},
		},
		{
			name:   "should fail if the openebs configuration is invalid",
			scname: "default",
			err:    "failed to parse openebs config annotation",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
						Annotations: map[string]string{
							"cas.openebs.io/config": "...---...<<>>",
						},
					},
				},
			},
		},
		{
			name:   "should fail if opeenbs configuration does not contain the base path",
			scname: "default",
			err:    "openebs base path not defined in the storage class",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
						Annotations: map[string]string{
							"cas.openebs.io/config": "- name: abc\n  value: cba",
						},
					},
				},
			},
		},
		{
			name:   "should fail if opeenbs base path is empty",
			scname: "default",
			err:    "invalid opeenbs base path",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
						Annotations: map[string]string{
							"cas.openebs.io/config": "- name: BasePath\n  value: \"\"",
						},
					},
				},
			},
		},
		{
			name:   "should fail if openebs base path is not a path",
			scname: "default",
			err:    "invalid opeenbs base path",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
						Annotations: map[string]string{
							"cas.openebs.io/config": "- name: BasePath\n  value: invalid",
						},
					},
				},
			},
		},
		{
			name:     "should be able to parse openebs configuration",
			scname:   "default",
			expected: "/var/local",
			objs: []runtime.Object{
				&storagev1.StorageClass{
					ObjectMeta: metav1.ObjectMeta{
						Name: "default",
						Annotations: map[string]string{
							"cas.openebs.io/config": "- name: BasePath\n  value: /var/local",
						},
					},
				},
			},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			fakecli := fake.NewSimpleClientset(tt.objs...)
			ochecker := OpenEBSFreeDiskSpaceGetter{
				kcli:   fakecli,
				scname: tt.scname,
			}

			bpath, err := ochecker.basePath(context.Background())
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

			if bpath != tt.expected {
				t.Errorf("expected %v, received %v", tt.expected, bpath)
			}
		})
	}
}

func Test_buildJob(t *testing.T) {
	nname := "this-is-a-very-long-node-name-this-will-extrapolate-the-limit"
	ochecker := OpenEBSFreeDiskSpaceGetter{image: "myimage:latest"}
	job := ochecker.buildJob(context.Background(), nname, "/var/local", "tmppvc")

	// check that the job name is within boundaries
	if len(job.Name) > 63 {
		t.Errorf("job name is bigger than the limit (63)")
	}

	// check that the job will run in the default namespace
	if job.Namespace != "default" {
		t.Errorf("job not going to run in the default namespace: %s", job.Namespace)
	}

	// check that the job is being scheduled in the right node
	affinity := job.Spec.Template.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution
	if affinity.NodeSelectorTerms[0].MatchExpressions[0].Values[0] != nname {
		t.Errorf("node has not be set to be scheduled in the node")
	}

	// assure that the temp pvc is among the volumes
	var mountName string
	for _, vol := range job.Spec.Template.Spec.Volumes {
		pvc := vol.VolumeSource.PersistentVolumeClaim
		if pvc == nil || pvc.ClaimName != "tmppvc" {
			continue
		}

		mountName = vol.Name
		break
	}
	if mountName == "" {
		t.Errorf("temp pvc not found among volumes")
	}

	// assure that the temp pvc is mounted
	var found bool
	for _, vm := range job.Spec.Template.Spec.Containers[0].VolumeMounts {
		if vm.Name == mountName {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("temp pvc not mounted")
	}

	// assure all containers are using the image
	for i, cont := range job.Spec.Template.Spec.Containers {
		if cont.Image != "myimage:latest" {
			t.Errorf("image not set in container %d: %s", i, cont.Image)
		}
	}
}

func TestNewOpenEBSVolumesGetter(t *testing.T) {
	// test empty logger
	_, err := NewOpenEBSFreeDiskSpaceGetter(nil, nil, "image", "scname")
	if err == nil || err.Error() != "no logger provided" {
		t.Errorf("expected failure creating object: %v", err)
	}

	logger := log.New(io.Discard, "", 0)

	// test empty image
	_, err = NewOpenEBSFreeDiskSpaceGetter(nil, logger, "", "scname")
	if err == nil || err.Error() != "empty image" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// test empty sc name
	_, err = NewOpenEBSFreeDiskSpaceGetter(nil, logger, "image", "")
	if err == nil || err.Error() != "empty storage class" {
		t.Errorf("expected failure creating object: %v", err)
	}

	// happy path
	_, err = NewOpenEBSFreeDiskSpaceGetter(nil, logger, "image", "scname")
	if err != nil {
		t.Errorf("unexpected failure creating object: %v", err)
	}
}
