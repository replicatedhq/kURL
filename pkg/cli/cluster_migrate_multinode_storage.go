package cli

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v2"
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
}

func NewClusterMigrateMultinodeStorageCmd(cli CLI) *cobra.Command {
	opts := migrateOpts{log: cli.Logger()}
	cmd := &cobra.Command{
		Use:          "migrate-multinode-storage",
		Short:        "Migrate persistent volumes from 'scaling' to 'distributed' storage classes.",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.GetConfig()
			if err != nil {
				return fmt.Errorf("failed to get kubernetes config: %w", err)
			}
			client, err := kubernetes.NewForConfig(cfg)
			if err != nil {
				return fmt.Errorf("failed to get kubernetes client: %w", err)
			}
			opts.log.Printf("reading ekco operator credentials.")
			if opts.authToken, err = getEkcoStorageMigrationAuthToken(cmd.Context(), client); err != nil {
				return fmt.Errorf("failed to get ekco storage migration auth token: %w", err)
			}
			opts.log.Printf("finding ekco operator http address.")
			if opts.ekcoAddress, err = getEkcoAddress(cmd.Context(), client); err != nil {
				return fmt.Errorf("failed to get ekco address: %w", err)
			}
			return runStorageMigration(cmd.Context(), opts)
		},
	}
	cmd.Flags().DurationVar(&opts.readyTimeout, "ready-timeout", 10*time.Minute, "Timeout waiting cluster to be ready for the storage migration.")
	cmd.Flags().DurationVar(&opts.migrateTimeout, "migrate-timeout", 8*time.Hour, "Timeout waiting for the storage migration to finish.")
	return cmd
}

// getEkcoStorageMigrationAuthToken parses the ekco config map and looks for the storage_migration_auth_token property.
// this field may be empty, on this case this function returns an empty string.
func getEkcoStorageMigrationAuthToken(ctx context.Context, cli kubernetes.Interface) (string, error) {
	cm, err := cli.CoreV1().ConfigMaps(ekcoNamespace).Get(ctx, ekcoConfigConfigMap, metav1.GetOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to get ekco configmap: %w", err)
	}
	rawConfig, ok := cm.Data["config.yaml"]
	if !ok {
		return "", fmt.Errorf("failed to find config.yaml in ekco configuration")
	}
	result := map[string]interface{}{}
	if err := yaml.Unmarshal([]byte(rawConfig), &result); err != nil {
		return "", fmt.Errorf("failed to unmarshal ekco config: %w", err)
	}
	if token, ok := result["storage_migration_auth_token"]; ok {
		if tokenStr, ok := token.(string); ok {
			return tokenStr, nil
		}
		return "", fmt.Errorf("failed to parse ekco config: storage_migration_auth_token is not a string")
	}
	return "", nil
}

// getEkcoAddress returns the address of the ekco pod. address is composed by the ip address and the port for http
// connection. if zero or more than one ekco pod is found this function returns an error. XXX shouldn't we expose
// ekco through a service instead?
func getEkcoAddress(ctx context.Context, cli kubernetes.Interface) (string, error) {
	pods, err := cli.CoreV1().Pods(ekcoNamespace).List(ctx, metav1.ListOptions{LabelSelector: ekcoPodsSelector})
	if err != nil {
		return "", fmt.Errorf("failed to list ekco pods: %w", err)
	}
	if len(pods.Items) == 0 {
		return "", fmt.Errorf("failed to find ekco pod: no ekco pods found")
	} else if len(pods.Items) > 1 {
		return "", fmt.Errorf("failed to find ekco pod: multiple ekco pods found")
	}
	return fmt.Sprintf("%s:%d", pods.Items[0].Status.PodIP, ekcoPort), nil
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

// isEkcoReadyForStorageMigration returns true if ekco reports that it is ready for a storage migration. this relies
// solely on ekco returning a 200 status with the "migration ready" message. XXX wouldn't be better to base this on
// different http response codes?
func isEkcoReadyForStorageMigration(opts migrateOpts) (bool, error) {
	url := fmt.Sprintf("http://%s/storagemigration/ready", opts.ekcoAddress)
	resp, err := http.Get(url)
	if err != nil {
		return false, fmt.Errorf("failed to get ekco status: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Errorf("failed to read ekco status response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("failed to get ekco status (%d): %s", resp.StatusCode, string(body))
	}
	return string(body) == "migration ready", nil
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

func runStorageMigration(ctx context.Context, opts migrateOpts) error {
	if status, err := getEkcoMigrationStatus(opts); err != nil {
		return fmt.Errorf("failed to read current status migration: %w", err)
	} else if status == ekcoMigrationStatusCompleted {
		opts.log.Printf("cluster storage migration already marked as completed.")
		return nil
	}
	readyfn := func(ctx context.Context) (bool, error) {
		ready, err := isEkcoReadyForStorageMigration(opts)
		if err != nil {
			return false, err
		}
		opts.log.Printf("cluster reporting ready for migration: %v", ready)
		return ready, nil
	}
	readyCtx, cancel := context.WithTimeout(ctx, opts.readyTimeout)
	defer cancel()
	opts.log.Printf("waiting cluster to report as ready for storage migration (%s timeout).", opts.readyTimeout)
	if err := wait.PollUntilContextCancel(readyCtx, 5*time.Second, true, readyfn); err != nil {
		return fmt.Errorf("failed to wait for ekco to be ready for migration: %w", err)
	}
	opts.log.Printf("approving cluster storage migration.")
	if err := approveStorageMigration(opts); err != nil {
		log.Fatal(err)
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
