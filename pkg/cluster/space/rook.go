package clusterspace

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"

	"code.cloudfoundry.org/bytefmt"
	"github.com/replicatedhq/kurl/pkg/k8sutil"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// RookChecker checks if we have enough disk space to migrate volumes to rook. uses the rook-ceph-tool pod to fetch
// the free space and then compare it with all allocated space for all volumes of source storage class (srcSC).
type RookChecker struct {
	cli    kubernetes.Interface
	cfg    *rest.Config
	log    *log.Logger
	kutils *K8SUtils
	srcSC  string
}

// CephData represents the unmarshaled output of a "ceph df -f json" command output.
type CephData struct {
	Stats struct {
		TotalAvalBytes int64 `json:"total_avail_bytes"`
	} `json:"stats"`
}

// freeSpace attempts to get the ceph free space by exec'ing "ceph df -f json" into rook ceph tools pod and parsing
// the output. returns the number of available bytes.
func (r *RookChecker) freeSpace(ctx context.Context) (int64, error) {
	namespace := "rook-ceph"
	deployment := "rook-ceph-tools"
	pods, err := k8sutil.DeploymentPods(ctx, r.cli, namespace, deployment)
	if err != nil {
		return 0, fmt.Errorf("failed to find ceph tools pod: %w", err)
	}

	if len(pods) == 0 {
		return 0, fmt.Errorf("no pod found for deployment rook-ceph-tools")
	}

	podname := pods[0].Name
	corecli := r.cli.CoreV1()
	cmd := []string{"ceph", "df", "-f", "json"}
	ecode, stdout, stderr, err := k8sutil.SyncExec(corecli, r.cfg, namespace, podname, "", cmd...)
	if err != nil {
		return 0, fmt.Errorf("failed to execute command on rook-ceph-tools-pod: %w", err)
	}

	logCommandOutputs := func() {
		r.log.Printf("failed to get free ceph storage on pod %s:", podname)
		r.log.Printf("exit code: %d", ecode)
		r.log.Printf("stdout:\n %s", stdout)
		r.log.Printf("stderr:\n %s", stderr)
	}

	var parsed bool
	var cephdata CephData
	buf := bytes.NewBuffer([]byte(stdout))
	scanner := bufio.NewScanner(buf)
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		if err := json.Unmarshal(line, &cephdata); err != nil {
			logCommandOutputs()
			return 0, fmt.Errorf("failed to parse rook ceph tools pod output: %w", err)
		}

		parsed = true
		break
	}

	if !parsed {
		logCommandOutputs()
		return 0, fmt.Errorf("failed to parse rook ceph tools pod output")
	}

	return cephdata.Stats.TotalAvalBytes, nil
}

// reservedSpace returns the total size of all volumes using the source storage class (srcSC).
func (r *RookChecker) reservedSpace(ctx context.Context) (int64, error) {
	usedPerNode, usedDetached, err := r.kutils.PVSReservationPerNode(ctx, r.srcSC)
	if err != nil {
		return 0, fmt.Errorf("failed to calculate used disk space per node: %w", err)
	}

	total := usedDetached
	for _, used := range usedPerNode {
		total += used
	}

	return total, nil
}

// Check verifies if there is enough ceph disk space to migrate from the source storage class.
func (r *RookChecker) Check(ctx context.Context) (bool, error) {
	r.log.Print("Analysing reserved and free Ceph disk space...")
	free, err := r.freeSpace(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to verify free space: %w", err)
	}

	reserved, err := r.reservedSpace(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to calculate used space: %w", err)
	}

	r.log.Print("\n")
	r.log.Printf("Free space in Ceph: %s", bytefmt.ByteSize(uint64(free)))
	r.log.Printf("Reserved (%q storage class): %s", r.srcSC, bytefmt.ByteSize(uint64(reserved)))
	r.log.Print("\n")
	return free > reserved, nil
}

// NewRookChecker returns a disk free analyser for rook storage provisioner.
func NewRookChecker(cli kubernetes.Interface, log *log.Logger, cfg *rest.Config, srcSC string) *RookChecker {
	return &RookChecker{
		cli:    cli,
		cfg:    cfg,
		log:    log,
		srcSC:  srcSC,
		kutils: NewK8sUtils(log, cli, cfg),
	}
}
