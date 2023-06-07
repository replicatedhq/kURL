package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/util/wait"

	"github.com/spf13/cobra"
)

const (
	ekcoConfigConfigMap          = "ekco-config"
	ekcoPodsSelector             = "app=ekc-operator"
	ekcoPort                     = 8080
	ekcoMigrationStatusFailed    = "failed"
	ekcoMigrationStatusCompleted = "completed"
)

type migrateOpts struct {
	log            *log.Logger
	authToken      string
	ekcoAddress    string
	readyTimeout   time.Duration
	migrateTimeout time.Duration
	minimumNrNodes int
}

func NewClusterMigrateMultinodeStorageCmd(cli CLI) *cobra.Command {
	opts := migrateOpts{log: cli.Logger()}
	cmd := &cobra.Command{
		Use:   "migrate-multinode-storage",
		Short: "Migrate persistent volumes from 'scaling' to 'distributed' storage classes.",
		PreRunE: func(cmd *cobra.Command, args []string) error {
			if opts.minimumNrNodes <= 0 {
				return fmt.Errorf("--minimum-number-of-nodes flag is required to be > 0.")
			}
			cmd.SilenceUsage = true
			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return runStorageMigration(cmd.Context(), opts)
		},
	}
	cmd.Flags().DurationVar(&opts.readyTimeout, "ready-timeout", 10*time.Minute, "Timeout waiting for the cluster to be ready for the storage migration.")
	cmd.Flags().DurationVar(&opts.migrateTimeout, "migrate-timeout", 8*time.Hour, "Timeout waiting for the storage migration to finish.")
	cmd.Flags().IntVar(&opts.minimumNrNodes, "minimum-number-of-nodes", 0, "Indicates the desired minimum number of nodes to start the migration.")
	cmd.Flags().StringVar(&opts.ekcoAddress, "ekco-address", "ecko.kurl:"+strconv.Itoa(ekcoPort), "The address of the ekco operator.")
	cmd.Flags().StringVar(&opts.authToken, "ekco-auth-token", "", "The auth token to use to authenticate with the ekco operator.")
	return cmd
}

// getEkcoMigrationLogs returns the logs of the migration as reported back by ekco.
func getEkcoMigrationLogs(opts migrateOpts) (string, error) {
	url := fmt.Sprintf("http://%s/storagemigration/logs", opts.ekcoAddress)
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to get migration logs: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read migration logs response: %w", err)
	}
	return string(body), nil
}

// getEkcoMigrationStatus returns the status of the storage migration as reported back by ekco.
func getEkcoMigrationStatus(opts migrateOpts) (string, error) {
	url := fmt.Sprintf("http://%s/storagemigration/status", opts.ekcoAddress)
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to get migration status: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read migration status response: %w", err)
	}
	return string(body), nil
}

// MigrationReady represents the status of the migration readiness check, includes a reason and also the number of
// nodes in the cluster.
type MigrationReadyStatus struct {
	Ready           bool   `json:"ready"`
	Reason          string `json:"reason"`
	NrNodes         int    `json:"nrNodes"`
	RequiredNrNodes int    `json:"requiredNrNodes"`
}

func isEkcoReadyForStorageMigration(opts migrateOpts) (*MigrationReadyStatus, error) {
	url := fmt.Sprintf("http://%s/storagemigration/ready", opts.ekcoAddress)
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to get ekco status: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read ekco status response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to get ekco status (%d): %s", resp.StatusCode, string(body))
	}
	var status MigrationReadyStatus
	if err := json.Unmarshal(body, &status); err != nil {
		return nil, fmt.Errorf("failed to unmarshal ekco status: %w", err)
	}
	return &status, nil
}

// approveStorageMigration tells ekco to start the storage migration.
func approveStorageMigration(opts migrateOpts) error {
	url := fmt.Sprintf("http://%s/storagemigration/approve", opts.ekcoAddress)
	req, err := http.NewRequest(http.MethodPost, url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", opts.authToken))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to approve storage migration: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to approve storage migration (%d): %s", resp.StatusCode, string(body))
	}
	return nil
}

func continueWithStorageMigration() bool {
	fmt.Println("    The installer detected both OpenEBS and Rook installations in your cluster. Migration from OpenEBS to Rook")
	fmt.Println("    is possible now, but it requires scaling down applications using OpenEBS volumes, causing downtime. You can")
	fmt.Println("    choose to run the migration later if preferred.")
	fmt.Print("Would you like to continue with the migration now? (Y/n) ")
	var answer string
	fmt.Scanln(&answer)
	return answer == "" || strings.ToLower(answer) == "y"
}

func runStorageMigration(ctx context.Context, opts migrateOpts) error {
	if status, err := getEkcoMigrationStatus(opts); err != nil {
		return fmt.Errorf("failed to read current status migration: %w", err)
	} else if status == ekcoMigrationStatusCompleted {
		opts.log.Printf("cluster storage migration already marked as completed.")
		return nil
	}
	if status, err := isEkcoReadyForStorageMigration(opts); err != nil {
		return fmt.Errorf("failed to check if cluster is ready for migration: %w", err)
	} else if status.NrNodes < opts.minimumNrNodes {
		return nil
	} else if !continueWithStorageMigration() {
		return nil
	}
	readyfn := func(ctx context.Context) (bool, error) {
		status, err := isEkcoReadyForStorageMigration(opts)
		if err != nil {
			return false, err
		}
		opts.log.Printf("cluster reporting ready for migration: %v", status.Reason)
		return status.Ready, nil
	}
	readyCtx, cancel := context.WithTimeout(ctx, opts.readyTimeout)
	defer cancel()
	opts.log.Printf("waiting cluster to report as ready for storage migration (%s timeout).", opts.readyTimeout)
	if err := wait.PollUntilContextCancel(readyCtx, 5*time.Second, true, readyfn); err != nil {
		return fmt.Errorf("failed to wait for ekco to be ready for migration: %w", err)
	}
	opts.log.Printf("approving cluster storage migration.")
	if err := approveStorageMigration(opts); err != nil {
		return fmt.Errorf("failed to approve storage migration: %w", err)
	}
	readyfn = func(ctx context.Context) (bool, error) {
		result, err := getEkcoMigrationStatus(opts)
		if err != nil {
			return false, err
		}
		if result == ekcoMigrationStatusFailed {
			return false, fmt.Errorf("failed to migrate storage classes")
		}
		opts.log.Printf("cluster reported migration status: %q", result)
		return result == ekcoMigrationStatusCompleted, nil
	}
	migrateCtx, cancel := context.WithTimeout(ctx, opts.migrateTimeout)
	defer cancel()
	opts.log.Printf("migration has been successfully approved, waiting for it to finish (%s timeout)...", opts.migrateTimeout)
	if err := wait.PollUntilContextCancel(migrateCtx, 5*time.Second, false, readyfn); err != nil {
		if logs, err := getEkcoMigrationLogs(opts); err == nil {
			opts.log.Printf("cluster storage migration failed, reading logs:")
			opts.log.Print(logs)
		}
		return fmt.Errorf("failed to wait for ekco to be ready for migration: %w", err)
	}
	return nil
}
