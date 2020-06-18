package runner

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	kubevirtv1 "kubevirt.io/client-go/api/v1"
)

var zero = int64(0)

func Run(singleTest types.SingleRun, uploadProxyURL string) error {
	err := execute(singleTest, uploadProxyURL)

	if err != nil {
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

func execute(singleTest types.SingleRun, uploadProxyURL string) error {
	// download the img (this should be cached)
	tempDir, err := ioutil.TempDir("", "")
	if err != nil {
		return errors.Wrap(err, "failed to create temp dir")
	}

	fmt.Printf("  [downloading from %s]\n", singleTest.OperatingSystemImage)

	// Download the img
	resp, err := http.Get(singleTest.OperatingSystemImage)
	if err != nil {
		return errors.Wrap(err, "failed to get")
	}
	defer resp.Body.Close()

	// Create the file
	out, err := os.Create(filepath.Join(tempDir, "vmimage"))
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

	cmd := exec.Command("kubectl",
		"virt",
		"image-upload",
		fmt.Sprintf("--uploadproxy-url=%s", uploadProxyURL),
		"--insecure",
		"--pvc-name",
		singleTest.PVCName,
		"--pvc-size=100Gi",
		fmt.Sprintf("--image-path=%s", filepath.Join(tempDir, "vmimage")),
	)

	output, err := cmd.Output()
	if err != nil {
		fmt.Printf("image-upload output: %s\n", output)
		return errors.Wrap(err, "command failed")
	}

	vmi := kubevirtv1.VirtualMachineInstance{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "kubevirt.io/v1alpha3",
			Kind:       "VirtualMachineInstance",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: singleTest.ID,
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
								Disk: &kubevirtv1.DiskTarget{
									Bus: "virtio",
								},
							},
						},
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
							UserData: fmt.Sprintf(`#cloud-config
password: kurl
chpasswd: { expire: False }
runcmd:
  - [ bash, -c, "curl %s | sudo timeout 15m bash" ]
  - [ bash, -c, 'curl -X POST --data-binary "@/var/log/cloud-init-output.log" %s/v1/instance/%s/logs']
  - [ bash, -c, '/opt/replicated/krew/bin/kubectl-support_bundle --kubeconfig /etc/kubernetes/admin.conf https://kots.io' ]
  - [ bash, -c, 'curl -X POST --data-binary "@/support-bundle.tar.gz" %s/v1/instance/%s/bundle' ]
  - [ bash, -c, 'mkdir -p /run/sonobuoy && curl -L --output /run/sonobuoy/sonobuoy.tar.gz https://github.com/vmware-tanzu/sonobuoy/releases/download/v0.18.3/sonobuoy_0.18.3_linux_amd64.tar.gz']
  - [ bash, -c, 'cd /usr/local/bin && tar xzvf /run/sonobuoy/sonobuoy.tar.gz']
  - [ bash, -c, 'sonobuoy --kubeconfig /etc/kubernetes/admin.conf run --wait --mode quick']
  - [ bash, -c, 'results=$(sonobuoy retrieve --kubeconfig /etc/kubernetes/admin.conf) && sonobuoy results $results > /tmp/sonobuoy-results.txt && curl -X POST --data-binary "@/tmp/sonobuoy-results.txt" %s/v1/instance/%s/sonobuoy' ]
  - [ bash, -c, 'curl -X POST %s/v1/instance/%s/finish']
power_state:
  mode: poweroff
  timeout: 1
  condition: True
`,
								singleTest.KurlURL,
								singleTest.TestGridAPIEndpoint, singleTest.ID,
								singleTest.TestGridAPIEndpoint, singleTest.ID,
								singleTest.TestGridAPIEndpoint, singleTest.ID,
								singleTest.TestGridAPIEndpoint, singleTest.ID),
						},
					},
				},
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

	output, err = cmd.Output()
	if err != nil {
		fmt.Printf("%s\n", output)
		return errors.Wrap(err, "command failed")
	}

	fmt.Printf("%s\n", output)

	return nil
}
