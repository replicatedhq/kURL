package runner

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"time"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	kubevirtv1 "kubevirt.io/client-go/api/v1"
)

var zero = int64(0)

func Run(singleTest types.SingleRun, uploadProxyURL, tempDir string) error {
	err := execute(singleTest, uploadProxyURL, tempDir)

	if err != nil {
		fmt.Println("execute failed")
		fmt.Println("  ID:", singleTest.ID)
		fmt.Println("  REF:", singleTest.KurlRef)
		fmt.Println("  ERROR:", err)
		if reportError := reportFailed(singleTest, err); reportError != nil {
			return errors.Wrap(err, "failed to report test failed")
		}
	}

	return nil
}

func reportStarted(singleTest types.SingleRun) error {
	startInstanceRequest := tghandlers.StartInstanceRequest{
		OSName:    singleTest.OperatingSystemName,
		OSVersion: singleTest.OperatingSystemVersion,
		OSImage:   singleTest.OperatingSystemImage,

		Memory: "16Gi",
		CPU:    "4",

		KurlSpec: singleTest.KurlYAML,
		KurlRef:  singleTest.KurlRef,
		KurlURL:  singleTest.KurlURL,
	}

	b, err := json.Marshal(startInstanceRequest)
	if err != nil {
		return errors.Wrap(err, "failed to marshal request")
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/instance/%s/start", singleTest.TestGridAPIEndpoint, singleTest.ID), bytes.NewReader(b))
	if err != nil {
		return errors.Wrap(err, "failed to create request")
	}
	req.Header.Set("Content-Type", "application/json")
	_, err = http.DefaultClient.Do(req)
	if err != nil {
		return errors.Wrap(err, "failed to execute request")
	}

	return nil
}

func reportFailed(singleTest types.SingleRun, testErr error) error {
	return nil
}

// pathify OS image by removing non-alphanumeric characters
func urlToPath(url string) string {
	return regexp.MustCompile(`[^a-zA-Z0-9]`).ReplaceAllString(url, "")
}

func execute(singleTest types.SingleRun, uploadProxyURL, tempDir string) error {
	osImagePath := urlToPath(singleTest.OperatingSystemImage)

	_, err := os.Stat(filepath.Join(tempDir, osImagePath))
	if err != nil {
		fmt.Printf("  [downloading from %s]\n", singleTest.OperatingSystemImage)

		// Download the img
		resp, err := http.Get(singleTest.OperatingSystemImage)
		if err != nil {
			return errors.Wrap(err, "failed to get")
		}
		defer resp.Body.Close()

		// Create the file
		out, err := os.Create(filepath.Join(tempDir, osImagePath))
		if err != nil {
			return errors.Wrap(err, "failed to create image file")
		}
		defer out.Close()

		// Write the body to file
		_, err = io.Copy(out, resp.Body)
		if err != nil {
			return errors.Wrap(err, "failed to save vm image")
		}

		fmt.Printf("   [image downloaded]\n")
	} else {
		fmt.Printf("  [using existng image on disk at %s for %s]\n", filepath.Join(tempDir, osImagePath), singleTest.OperatingSystemImage)
	}

	cmd := exec.Command("kubectl",
		"virt",
		"image-upload",
		fmt.Sprintf("--uploadproxy-url=%s", uploadProxyURL),
		"--insecure",
		"--pvc-name",
		singleTest.PVCName,
		"--pvc-size=100Gi",
		fmt.Sprintf("--image-path=%s", filepath.Join(tempDir, osImagePath)),
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("image-upload output: %s\n", output)
		return errors.Wrap(err, "kubectl apply pvc failed")
	}

	fmt.Printf("   [pvc created]\n")
	fmt.Printf("%s\n", output)

	if err := createSecret(singleTest, tempDir); err != nil {
		return errors.Wrap(err, "create secret failed")
	}
	fmt.Printf("   [secret created]\n")

	vmi := kubevirtv1.VirtualMachineInstance{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "kubevirt.io/v1alpha3",
			Kind:       "VirtualMachineInstance",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: singleTest.ID,
			Labels: map[string]string{
				"kubevirt.io/domain": singleTest.ID,
			},
			Annotations: map[string]string{
				"testgrid.kurl.sh/osname":    singleTest.OperatingSystemName,
				"testgrid.kurl.sh/osversion": singleTest.OperatingSystemVersion,
				"testgrid.kurl.sh/osimage":   singleTest.OperatingSystemImage,
				"testgrid.kurl.sh/kurlurl":   singleTest.KurlURL,
			},
		},
		Spec: kubevirtv1.VirtualMachineInstanceSpec{
			Domain: kubevirtv1.DomainSpec{
				Machine: kubevirtv1.Machine{
					Type: "",
				},
				Resources: kubevirtv1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceName(corev1.ResourceMemory): resource.MustParse("16Gi"),
						corev1.ResourceName(corev1.ResourceCPU):    resource.MustParse("4"),
					},
				},
				Devices: kubevirtv1.Devices{
					Disks: []kubevirtv1.Disk{
						{
							Name: "pvcdisk",
							DiskDevice: kubevirtv1.DiskDevice{
								Disk: &kubevirtv1.DiskTarget{
									Bus: "virtio",
								},
							},
						},
						{
							Name: "cloudinitdisk",
							DiskDevice: kubevirtv1.DiskDevice{
								CDRom: &kubevirtv1.CDRomTarget{
									Bus: "sata",
								},
							},
						},
						getEmptyDisk("emptydisk1"),
					},
				},
			},
			TerminationGracePeriodSeconds: &zero,
			Volumes: []kubevirtv1.Volume{
				{
					Name: "pvcdisk",
					VolumeSource: kubevirtv1.VolumeSource{
						PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
							ClaimName: singleTest.PVCName,
						},
					},
				},
				{
					Name: "cloudinitdisk",
					VolumeSource: kubevirtv1.VolumeSource{
						CloudInitNoCloud: &kubevirtv1.CloudInitNoCloudSource{
							UserDataSecretRef: &corev1.LocalObjectReference{
								Name: fmt.Sprintf("cloud-init-%s", singleTest.ID),
							},
						},
					},
				},
				getEmptyDiskVolume("emptydisk1", resource.MustParse("50Gi")),
			},
		},
	}

	// it would be nice to add the client-go from kubevirt, but
	// go mod is making it really hard
	b, err := json.Marshal(vmi)
	if err != nil {
		return errors.Wrap(err, "failed to marshal vmi")
	}
	if err := ioutil.WriteFile(filepath.Join(tempDir, "vmi.yaml"), b, 0644); err != nil {
		return errors.Wrap(err, "failed to write file")
	}

	// mark the instance started
	// we do this after the data volume is uploaded
	if err := reportStarted(singleTest); err != nil {
		return errors.Wrap(err, "failed to report test started")
	}

	cmd = exec.Command("kubectl",
		"apply",
		"-f",
		filepath.Join(tempDir, "vmi.yaml"),
	)

	output, err = cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s\n", output)
		return errors.Wrap(err, "kubectl apply vmi failed")
	}

	fmt.Printf("   [vmi created]\n")
	fmt.Printf("%s\n", output)

	return nil
}

func createSecret(singleTest types.SingleRun, tempDir string) error {
	runcmdB64 := base64.StdEncoding.EncodeToString([]byte(runcmdSh))

	varsSh := fmt.Sprintf(`
export TESTGRID_APIENDPOINT='%s'
export TEST_ID='%s'
export KURL_URL='%s'
export KURL_UPGRADE_URL='%s'
export DOCKERHUB_USERNAME='%s'
export DOCKERHUB_PASSWORD='%s'
`,
		singleTest.TestGridAPIEndpoint, singleTest.ID, singleTest.KurlURL, singleTest.UpgradeURL,
		os.Getenv("DOCKERHUB_USERNAME"), os.Getenv("DOCKERHUB_PASSWORD"))

	varsB64 := base64.StdEncoding.EncodeToString([]byte(varsSh))

	script := fmt.Sprintf(`#cloud-config

password: kurl
chpasswd: { expire: False }

output: { all: "| tee -a /var/log/cloud-init-output.log" }

runcmd:
  - [ bash, -c, 'sudo mkdir -p /opt/kurl-testgrid' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/vars.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/runcmd.sh' ]
  - [ bash, -c, 'sudo bash -c ". /opt/kurl-testgrid/vars.sh && bash /opt/kurl-testgrid/runcmd.sh"' ]
  - [ bash, -c, 'sleep 10 && sudo poweroff' ]

power_state:
  mode: poweroff
  condition: True
`,
		varsB64,
		runcmdB64,
	)

	file := filepath.Join(tempDir, "startup-script.sh")

	if err := ioutil.WriteFile(file, []byte(script), 0755); err != nil {
		return errors.Wrap(err, "failed to write secret to file")
	}
	defer os.Remove(file)

	cmd := exec.Command("kubectl", "create", "secret", "generic",
		fmt.Sprintf("cloud-init-%s", singleTest.ID),
		fmt.Sprintf("--from-file=userdata=%s", file),
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("%s\n", output)
		return errors.Wrap(err, "kubectl create secret failed")
	}

	return nil
}

func getEmptyDisk(name string) kubevirtv1.Disk {
	return kubevirtv1.Disk{
		Name:   name,
		Serial: randomStringWithCharset(serialLen, serialCharset),
		DiskDevice: kubevirtv1.DiskDevice{
			Disk: &kubevirtv1.DiskTarget{
				Bus: "virtio",
			},
		},
	}
}

func getEmptyDiskVolume(name string, capacity resource.Quantity) kubevirtv1.Volume {
	return kubevirtv1.Volume{
		Name: name,
		VolumeSource: kubevirtv1.VolumeSource{
			EmptyDisk: &kubevirtv1.EmptyDiskSource{
				Capacity: capacity,
			},
		},
	}
}

const (
	serialLen     = 16
	serialCharset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
)

var seededRand *rand.Rand = rand.New(rand.NewSource(time.Now().UnixNano()))

func randomStringWithCharset(length int, charset string) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[seededRand.Intn(len(charset))]
	}
	return string(b)
}
