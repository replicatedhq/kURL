package vmi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/pkg/errors"
	tghandlers "github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/helpers"
	"github.com/replicatedhq/kurl/testgrid/tgrun/pkg/runner/types"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	kubevirtv1 "kubevirt.io/api/core/v1"
)

const (
	InitPrimaryNode       = "initialprimary"
	SecondaryNode         = "secondary"
	PrimaryNode           = "primary"
	serialLen             = 16
	serialCharset         = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	ApiEndpointAnnotation = "testgrid.kurl.sh/apiendpoint"
	KurlURLAnnotation     = "testgrid.kurl.sh/kurlurl"
	OSImageAnnotation     = "testgrid.kurl.sh/osimage"
	OSVersionAnnotation   = "testgrid.kurl.sh/osversion"
	OSNameAnnotation      = "testgrid.kurl.sh/osname"
	TestIDAnnotation      = "testgrid.kurl.sh/testid"
)

var zero = int64(0)
var seededRand *rand.Rand = rand.New(rand.NewSource(time.Now().UnixNano()))

func Create(singleTest types.SingleRun, nodeName string, nodeType string, tempDir string, osImagePath string, uploadProxyURL string) error {

	if err := createPvc(singleTest, nodeName, tempDir, osImagePath, uploadProxyURL); err != nil {
		return errors.Wrap(err, "failed to create PVC")
	}
	fmt.Printf("   [pvc created]\n")

	if err := createSecret(singleTest, nodeName); err != nil {
		return errors.Wrap(err, "create secret failed")
	}
	fmt.Printf("   [secret created]\n")

	if err := createK8sNode(singleTest, nodeName); err != nil {
		return errors.Wrap(err, "node creation failed")
	}
	fmt.Printf("   [vmi created]\n")
	if err := AddNodeCluster(singleTest, nodeName, nodeType); err != nil {
		return errors.Wrap(err, "failed to add node to nodecluster table")
	}
	fmt.Printf("   [node has been added to the clusternode table in created status]\n")
	return nil
}

func SendLogs(apiEndpoint, nodeID string) error {
	if err := createSendlogsSecret(apiEndpoint, nodeID); err != nil {
		return fmt.Errorf("unable to create sendlogs secret: %w", err)
	}

	if err := createSendlogsNode(nodeID); err != nil {
		return fmt.Errorf("unable to create sendlogs node: %w", err)
	}

	return nil
}

func createPvc(singleTest types.SingleRun, nodeName string, tempDir string, osImagePath string, uploadProxyURL string) error {
	name := fmt.Sprintf("%s-%s-disk", singleTest.PVCName, nodeName)
	cmd := exec.Command("kubectl",
		"virt",
		"image-upload",
		fmt.Sprintf("--uploadproxy-url=%s", uploadProxyURL),
		"--insecure",
		"--pvc-name",
		name,
		"--pvc-size=100Gi",
		fmt.Sprintf("--image-path=%s", filepath.Join(tempDir, osImagePath)),
	)
	fmt.Println("cmd: ", cmd)
	output, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("image-upload output: %s\n", output)
		return errors.Wrap(err, "kubectl apply pvc failed")
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

func randomStringWithCharset(length int, charset string) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[seededRand.Intn(len(charset))]
	}
	return string(b)
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

func createSendlogsSecret(apiEndpoint, nodeID string) error {
	client, err := helpers.GetClientset()
	if err != nil {
		return fmt.Errorf("failed to get clientset: %w", err)
	}

	finalizeB64 := base64.StdEncoding.EncodeToString(finalizeLogs)

	varsSh := fmt.Sprintf(`
export TESTGRID_APIENDPOINT='%s'
export NODE_ID='%s'
`, apiEndpoint, nodeID)
	varsB64 := base64.StdEncoding.EncodeToString([]byte(varsSh))

	script := fmt.Sprintf(`#cloud-config

password: kurl
chpasswd: { expire: False }

output: { all: "| tee -a /var/log/cloud-init-sendlogs-output.log" }

runcmd:
  - [ bash, -c, 'sudo mkdir -p /opt/kurl-testgrid' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/vars.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/finalizelogs.sh' ]
  - [ bash, -c, 'sudo bash -c ". /opt/kurl-testgrid/vars.sh && bash /opt/kurl-testgrid/finalizelogs.sh"' ]
  - [ bash, -c, 'sleep 10 && sudo poweroff' ]

power_state:
  mode: poweroff
  condition: True
`,
		varsB64,
		finalizeB64,
	)

	startupSecret := corev1.Secret{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "v1",
			Kind:       "Secret",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: fmt.Sprintf("cloud-init-%s-sendlogs", nodeID),
		},
		StringData: map[string]string{
			"userdata": script,
		},
		Type: corev1.SecretTypeOpaque,
	}
	_, err = client.CoreV1().Secrets("default").Create(context.TODO(), &startupSecret, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create secret: %w", err)
	}

	return nil
}

func createSecret(singleTest types.SingleRun, nodeName string) error {
	client, err := helpers.GetClientset()
	if err != nil {
		return fmt.Errorf("failed to get clientset: %w", err)
	}

	name, nodeId := fmt.Sprintf("%s-%s", singleTest.ID, nodeName), fmt.Sprintf("%s-%s", singleTest.ID, nodeName)
	runcmdB64 := base64.StdEncoding.EncodeToString(runcmdSh)
	if strings.HasPrefix(nodeName, SecondaryNode) {
		runcmdB64 = base64.StdEncoding.EncodeToString(secondarynodecmd)
	} else if strings.HasPrefix(nodeName, PrimaryNode) {
		runcmdB64 = base64.StdEncoding.EncodeToString(primarynodecmd)
	}
	commonShB64 := base64.StdEncoding.EncodeToString(commonSh)
	mainScriptB64 := base64.StdEncoding.EncodeToString(mainscript)
	testHelpersB64 := base64.StdEncoding.EncodeToString(testHelpers)
	varsSh := fmt.Sprintf(`
export TESTGRID_APIENDPOINT='%s'
export TEST_ID='%s'
export KURL_URL='%s'
export KURL_FLAGS='%s'
export KURL_UPGRADE_URL='%s'
export SUPPORTBUNDLE_SPEC='%s'
export OS_NAME='%s'
export NUM_NODES='%d'
export NUM_PRIMARY_NODES='%d'
export NODE_ID='%s'
`,
		singleTest.TestGridAPIEndpoint,
		singleTest.ID,
		singleTest.KurlURL,
		singleTest.KurlFlags,
		singleTest.UpgradeURL,
		singleTest.SupportbundleYAML,
		singleTest.OperatingSystemName,
		max(singleTest.NumPrimaryNodes+singleTest.NumSecondaryNodes, 1),
		max(singleTest.NumPrimaryNodes, 1),
		nodeId,
	)

	varsB64 := base64.StdEncoding.EncodeToString([]byte(varsSh))

	postInstallB64 := base64.StdEncoding.EncodeToString([]byte(singleTest.PostInstallScript))
	postUpgradeB64 := base64.StdEncoding.EncodeToString([]byte(singleTest.PostUpgradeScript))

	script := fmt.Sprintf(`#cloud-config

password: kurl
chpasswd: { expire: False }

output: { all: "| tee -a /var/log/cloud-init-output.log" }

runcmd:
  - [ bash, -c, 'sudo mkdir -p /opt/kurl-testgrid' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/preinit.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/vars.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/common.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/runcmd.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/mainscript.sh' ]
  - [ bash, -c, 'echo %s | base64 -d > /opt/kurl-testgrid/testhelpers.sh' ]
  - [ bash, -c, '[ %d -eq 0 ] || echo %s | base64 -d > /opt/kurl-testgrid/postinstall.sh' ]
  - [ bash, -c, '[ %d -eq 0 ] || echo %s | base64 -d > /opt/kurl-testgrid/postupgrade.sh' ]
  - [ bash, -c, 'sudo bash /opt/kurl-testgrid/preinit.sh' ]
  - [ bash, -c, 'sudo bash -c ". /opt/kurl-testgrid/vars.sh && bash /opt/kurl-testgrid/mainscript.sh"' ]
  - [ bash, -c, 'sleep 10 && sudo poweroff' ]

power_state:
  mode: poweroff
  condition: True
`,
		base64.StdEncoding.EncodeToString([]byte(singleTest.OperatingSystemPreInit)),
		varsB64,
		commonShB64,
		runcmdB64,
		mainScriptB64,
		testHelpersB64,
		len(singleTest.PostInstallScript),
		postInstallB64,
		len(singleTest.PostUpgradeScript),
		postUpgradeB64,
	)

	startupSecret := corev1.Secret{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "v1",
			Kind:       "Secret",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: fmt.Sprintf("cloud-init-%s", name),
		},
		StringData: map[string]string{
			"userdata": script,
		},
		Type: corev1.SecretTypeOpaque,
	}
	_, err = client.CoreV1().Secrets("default").Create(context.TODO(), &startupSecret, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create secret: %w", err)
	}

	return nil
}

func createK8sNode(singleTest types.SingleRun, nodeName string) error {
	virtClient, err := helpers.GetKubevirtClientset()
	if err != nil {
		return fmt.Errorf("failed to get clientset: %w", err)
	}

	name := fmt.Sprintf("%s-%s", singleTest.ID, nodeName)
	pvcName := fmt.Sprintf("%s-%s-disk", singleTest.PVCName, nodeName)
	vmi := kubevirtv1.VirtualMachineInstance{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "kubevirt.io/v1alpha3",
			Kind:       "VirtualMachineInstance",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				"kubevirt.io/domain": name,
			},
			Annotations: map[string]string{
				OSNameAnnotation:      singleTest.OperatingSystemName,
				OSVersionAnnotation:   singleTest.OperatingSystemVersion,
				OSImageAnnotation:     singleTest.OperatingSystemImage,
				KurlURLAnnotation:     singleTest.KurlURL,
				ApiEndpointAnnotation: singleTest.TestGridAPIEndpoint,
				TestIDAnnotation:      singleTest.ID,
			},
		},
		Spec: kubevirtv1.VirtualMachineInstanceSpec{
			Domain: kubevirtv1.DomainSpec{
				Machine: &kubevirtv1.Machine{
					Type: "",
				},
				Resources: kubevirtv1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceMemory: resource.MustParse(singleTest.Memory),
						corev1.ResourceCPU:    resource.MustParse(singleTest.CPU),
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
						PersistentVolumeClaim: &kubevirtv1.PersistentVolumeClaimVolumeSource{
							PersistentVolumeClaimVolumeSource: corev1.PersistentVolumeClaimVolumeSource{
								ClaimName: pvcName,
							},
						},
					},
				},
				{
					Name: "cloudinitdisk",
					VolumeSource: kubevirtv1.VolumeSource{
						CloudInitNoCloud: &kubevirtv1.CloudInitNoCloudSource{
							UserDataSecretRef: &corev1.LocalObjectReference{
								Name: fmt.Sprintf("cloud-init-%s", name),
							},
						},
					},
				},
				getEmptyDiskVolume("emptydisk1", resource.MustParse("50Gi")),
			},
		},
	}

	_, err = virtClient.VirtualMachineInstance("default").Create(&vmi)
	if err != nil {
		return fmt.Errorf("failed to create VMI %s: %w", name, err)
	}

	return nil
}

func createSendlogsNode(nodeID string) error {
	virtClient, err := helpers.GetKubevirtClientset()
	if err != nil {
		return fmt.Errorf("failed to get clientset: %w", err)
	}

	pvcName := fmt.Sprintf("%s-disk", nodeID)
	vmi := kubevirtv1.VirtualMachineInstance{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "kubevirt.io/v1alpha3",
			Kind:       "VirtualMachineInstance",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: fmt.Sprintf("%s-sendlogs", nodeID),
			Labels: map[string]string{
				"kubevirt.io/domain": fmt.Sprintf("%s-sendlogs", nodeID),
			},
		},
		Spec: kubevirtv1.VirtualMachineInstanceSpec{
			Domain: kubevirtv1.DomainSpec{
				Machine: &kubevirtv1.Machine{
					Type: "",
				},
				Resources: kubevirtv1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceMemory: resource.MustParse("1Gi"),
						corev1.ResourceCPU:    resource.MustParse("100m"),
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
						PersistentVolumeClaim: &kubevirtv1.PersistentVolumeClaimVolumeSource{
							PersistentVolumeClaimVolumeSource: corev1.PersistentVolumeClaimVolumeSource{
								ClaimName: pvcName,
							},
						},
					},
				},
				{
					Name: "cloudinitdisk",
					VolumeSource: kubevirtv1.VolumeSource{
						CloudInitNoCloud: &kubevirtv1.CloudInitNoCloudSource{
							UserDataSecretRef: &corev1.LocalObjectReference{
								Name: fmt.Sprintf("cloud-init-%s-sendlogs", nodeID),
							},
						},
					},
				},
				getEmptyDiskVolume("emptydisk1", resource.MustParse("50Gi")),
			},
		},
	}

	_, err = virtClient.VirtualMachineInstance("default").Create(&vmi)
	if err != nil {
		return fmt.Errorf("failed to create VMI %s: %w", fmt.Sprintf("%s-sendlogs", nodeID), err)
	}

	return nil
}

func AddNodeCluster(singleTest types.SingleRun, nodeName string, nodeType string) error {
	nodeId := fmt.Sprintf("%s-%s", singleTest.ID, nodeName)
	clusterNodeRequest := tghandlers.ClusterNodeRequest{
		NodeId:   nodeId,
		NodeType: nodeType,
		Status:   "created",
	}
	b, err := json.Marshal(clusterNodeRequest)
	if err != nil {
		return errors.Wrap(err, "failed to marshal request")
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/v1/instance/%s/cluster-node", singleTest.TestGridAPIEndpoint, singleTest.ID), bytes.NewReader(b))

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

func max(x, y int) int {
	if x < y {
		return y
	}
	return x
}
