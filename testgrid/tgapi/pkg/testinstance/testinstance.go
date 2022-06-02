package testinstance

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance/types"
	yaml "gopkg.in/yaml.v2"
)

type KurlInstaller struct {
	APIVersion string                 `json:"apiVersion" yaml:"apiVersion"`
	Kind       string                 `json:"kind" yaml:"kind"`
	Metadata   KurlInstallerMetadata  `json:"metadata" yaml:"metadata"`
	Spec       map[string]interface{} `json:"spec" yaml:"spec"`
}

type KurlInstallerMetadata struct {
	Name string `json:"name" yaml:"name"`
}

func Create(id, testName, refID, kurlYAML, kurlURL, kurlFlags, upgradeYAML, upgradeURL, supportbundleYAML, postInstallScript, postUpgradeScript, osName, osVersion, osImage, osPreInit string, numPrimaryNode int, numSecondaryNode int) error {
	pg := persistence.MustGetPGSession()

	query := `insert into testinstance (id, test_name, enqueued_at, testrun_ref, kurl_yaml, kurl_url, kurl_flags, upgrade_yaml, upgrade_url, supportbundle_yaml, post_install_script, post_upgrade_script, os_name, os_version, os_image, os_preinit, num_primary_nodes, num_secondary_nodes)
values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`
	if _, err := pg.Exec(query, id, testName, time.Now(), refID, kurlYAML, kurlURL, kurlFlags, upgradeYAML, upgradeURL, supportbundleYAML, postInstallScript, postUpgradeScript, osName, osVersion, osImage, osPreInit, numPrimaryNode, numSecondaryNode); err != nil {
		return errors.Wrap(err, "failed to insert")
	}

	return nil
}

func GetNextEnqueued() (*types.TestInstance, error) {
	db := persistence.MustGetPGSession()

	query := `with updated as (
update testinstance
set dequeued_at = now() where id in (
select id from testinstance
where dequeued_at is null
order by enqueued_at asc
limit 1) returning id, test_name, num_primary_nodes, num_secondary_nodes, dequeued_at, testrun_ref, kurl_yaml, kurl_url, kurl_flags, upgrade_yaml, upgrade_url, supportbundle_yaml, post_install_script, post_upgrade_script, os_name, os_version, os_image, os_preinit
) select id, test_name, num_primary_nodes, num_secondary_nodes, testrun_ref, kurl_yaml, kurl_url, kurl_flags, upgrade_yaml, upgrade_url, supportbundle_yaml, post_install_script, post_upgrade_script, os_name, os_version, os_image, os_preinit from updated`

	row := db.QueryRow(query)

	testInstance := types.TestInstance{}
	var testName, kurlFlags, upgradeYAML, upgradeURL, supportbundleYAML, postInstallScript, postUpgradeScript, osPreInit sql.NullString
	if err := row.Scan(
		&testInstance.ID,
		&testName,
		&testInstance.NumPrimaryNodes,
		&testInstance.NumSecondaryNodes,
		&testInstance.RefID,
		&testInstance.KurlYAML,
		&testInstance.KurlURL,
		&kurlFlags,
		&upgradeYAML,
		&upgradeURL,
		&supportbundleYAML,
		&postInstallScript,
		&postUpgradeScript,
		&testInstance.OSName,
		&testInstance.OSVersion,
		&testInstance.OSImage,
		&osPreInit,
	); err != nil {
		return nil, errors.Wrap(err, "failed to query test instance")
	}

	testInstance.TestName = testName.String
	testInstance.KurlFlags = kurlFlags.String
	testInstance.UpgradeYAML = upgradeYAML.String
	testInstance.UpgradeURL = upgradeURL.String
	testInstance.SupportbundleYAML = supportbundleYAML.String
	testInstance.PostInstallScript = postInstallScript.String
	testInstance.PostUpgradeScript = postUpgradeScript.String
	testInstance.OSPreInit = osPreInit.String

	return &testInstance, nil
}

func Start(id string) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set started_at = now() where id = $1`

	if _, err := db.Exec(query, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func Running(id string) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set running_at = now() where id = $1`

	if _, err := db.Exec(query, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func SetInstanceLogs(id string, logs []byte) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set output = $1 where id = $2`

	if _, err := db.Exec(query, logs, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func SetInstanceSonobuoyResults(id string, results []byte) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set sonobuoy_results = $1 where id = $2`

	if _, err := db.Exec(query, results, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

// SetInstanceFinishedAndSuccess sets is_success, failure_reason and finished_at.
func SetInstanceFinishedAndSuccess(id string, isSuccess bool, failureReason string) error {
	db := persistence.MustGetPGSession()

	var query string
	if isSuccess {
		// Failure cannot change to success.
		query = `update testinstance set is_success = $2, finished_at = now(), failure_reason = $3 where id = $1 and finished_at is null`
	} else if failureReason == "timeout" {
		// Timeout cannot change success to failure.
		query = `update testinstance set is_success = $2, finished_at = now(), failure_reason = $3 where id = $1 and is_success != true`
	} else {
		// Success can change to failure unless timeout.
		query = `update testinstance set is_success = $2, finished_at = now(), failure_reason = $3 where id = $1`
	}

	if _, err := db.Exec(query, id, isSuccess, failureReason); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func GetInstanceDuration(id string) (time.Duration, error) {
	db := persistence.MustGetPGSession()

	query := `select started_at, finished_at from testinstance where id = $1`

	row := db.QueryRow(query, id)

	var startedAt, finishedAt sql.NullTime
	if err := row.Scan(&startedAt, &finishedAt); err != nil {
		return -1, errors.Wrap(err, "failed to scan")
	}

	if !finishedAt.Valid {
		return -1, errors.New("completion time is not valid")
	}

	return finishedAt.Time.Sub(startedAt.Time), nil
}

func SetInstanceUnsupported(id string) error {
	db := persistence.MustGetPGSession()

	query := `
update testinstance set
is_success = false, is_unsupported = true,
dequeued_at = now(), started_at = now(), running_at = now(), finished_at = now()
where id = $1`
	if _, err := db.Exec(query, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

// List returns a list of test instances.
// Note: pagination (limit and offset) are applied to instances with distinct kurl URLs (instances with same kurl URL count as 1)
func List(refID string, limit int, offset int, addons map[string]string) ([]types.TestInstance, error) {
	db := persistence.MustGetPGSession()

	query := `SELECT ti.id, ti.test_name, ti.kurl_yaml, ti.kurl_url, ti.kurl_flags, ti.upgrade_yaml, ti.upgrade_url, ti.supportbundle_yaml, ti.post_install_script, ti.post_upgrade_script, ti.os_name, ti.os_version, ti.os_image, ti.enqueued_at, ti.dequeued_at, ti.started_at, ti.finished_at, ti.is_success, ti.failure_reason, ti.is_unsupported, ti.num_primary_nodes, ti.num_secondary_nodes
FROM testinstance ti
WHERE ti.testrun_ref = $1`

	// filter addons
	for addon, version := range addons {
		if version == "" {
			continue
		}
		query += fmt.Sprintf(` AND kurl_yaml::jsonb @> '{"spec":{"%s":{"version": "%s"}}}'::jsonb`, addon, version)
	}

	query += ` ORDER BY kurl_url, os_name, os_version`
	query += ` OFFSET $2`

	// pagination
	args := []interface{}{refID, offset}
	if limit > 0 {
		query += ` LIMIT $3`
		args = append(args, limit)
	}

	rows, err := db.Query(query, args...)
	if err != nil {
		return nil, errors.Wrap(err, "failed to query")
	}

	testInstances := []types.TestInstance{}

	for rows.Next() {
		testInstance := types.TestInstance{}

		var enqueuedAt sql.NullTime
		var dequeuedAt sql.NullTime
		var startedAt sql.NullTime
		var finishedAt sql.NullTime
		var isSuccess, isUnsupported sql.NullBool
		var testName, kurlFlags, upgradeYAML, upgradeURL, supportbundleYAML, postInstallScript, postUpgradeScript, failureReason sql.NullString
		if err := rows.Scan(
			&testInstance.ID,
			&testName,
			&testInstance.KurlYAML,
			&testInstance.KurlURL,
			&kurlFlags,
			&upgradeYAML,
			&upgradeURL,
			&supportbundleYAML,
			&postInstallScript,
			&postUpgradeScript,
			&testInstance.OSName,
			&testInstance.OSVersion,
			&testInstance.OSImage,
			&enqueuedAt,
			&dequeuedAt,
			&startedAt,
			&finishedAt,
			&isSuccess,
			&failureReason,
			&isUnsupported,
			&testInstance.NumPrimaryNodes,
			&testInstance.NumSecondaryNodes,
		); err != nil {
			return nil, errors.Wrap(err, "failed to scan")
		}

		if enqueuedAt.Valid {
			testInstance.EnqueuedAt = &enqueuedAt.Time
		}
		if dequeuedAt.Valid {
			testInstance.DequeuedAt = &dequeuedAt.Time
		}
		if startedAt.Valid {
			testInstance.StartedAt = &startedAt.Time
		}
		if finishedAt.Valid {
			testInstance.FinishedAt = &finishedAt.Time
		}

		testInstance.TestName = testName.String
		testInstance.IsSuccess = isSuccess.Bool
		testInstance.FailureReason = failureReason.String
		testInstance.IsUnsupported = isUnsupported.Bool
		testInstance.KurlFlags = kurlFlags.String
		testInstance.UpgradeYAML = upgradeYAML.String
		testInstance.UpgradeURL = upgradeURL.String
		testInstance.SupportbundleYAML = supportbundleYAML.String
		testInstance.PostInstallScript = postInstallScript.String
		testInstance.PostUpgradeScript = postUpgradeScript.String

		testInstances = append(testInstances, testInstance)
	}

	return testInstances, nil
}

func Total(refID string, addons map[string]string) (int, error) {
	db := persistence.MustGetPGSession()

	query := `select count(DISTINCT kurl_url) as total from testinstance where testrun_ref = $1`

	// filter addons
	for addon, version := range addons {
		if version == "" {
			continue
		}
		query += fmt.Sprintf(` and kurl_yaml::jsonb @> '{"spec":{"%s":{"version": "%s"}}}'::jsonb`, addon, version)
	}

	row := db.QueryRow(query, refID)

	var total int
	if err := row.Scan(&total); err != nil {
		return -1, errors.Wrap(err, "failed to scan")
	}

	return total, nil
}

func GetLogs(id string) (string, error) {
	db := persistence.MustGetPGSession()

	query := `select output from testinstance where id = $1`
	row := db.QueryRow(query, id)

	var logs sql.NullString
	if err := row.Scan(&logs); err != nil {
		return "", errors.Wrap(err, "failed to scan")
	}

	return logs.String, nil
}

func GetSonobuoyResults(id string) (string, error) {
	db := persistence.MustGetPGSession()

	query := `select sonobuoy_results from testinstance where id = $1`
	row := db.QueryRow(query, id)

	var results sql.NullString
	if err := row.Scan(&results); err != nil {
		return "", errors.Wrap(err, "failed to scan")
	}

	return results.String, nil
}

func GetUniqueAddons(refID string) ([]string, error) {
	db := persistence.MustGetPGSession()

	query := `select kurl_yaml from testinstance where testrun_ref = $1`
	rows, err := db.Query(query, refID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to query")
	}

	uniqueAddons := make(map[string]interface{})
	for rows.Next() {
		var kurlYaml sql.NullString
		if err := rows.Scan(&kurlYaml); err != nil {
			return nil, errors.Wrap(err, "failed to scan")
		}

		var kurlInstaller KurlInstaller
		if err := yaml.Unmarshal([]byte(kurlYaml.String), &kurlInstaller); err != nil {
			return nil, errors.Wrap(err, "failed to unmarshal")
		}

		for k := range kurlInstaller.Spec {
			uniqueAddons[k] = true
		}
	}

	addons := []string{}
	for addon := range uniqueAddons {
		addons = append(addons, addon)
	}

	return addons, nil
}

// GetTestStats returns the current numbers of pending, running, and timed out tests
func GetTestStats() (int64, int64, int64, error) {
	db := persistence.MustGetPGSession()

	query := `
select 
       count(1) FILTER (WHERE dequeued_at is null) as pending,
       count(1) FILTER (where dequeued_at is not null AND finished_at is null AND dequeued_at > now() - INTERVAL '3 hours') as running,
       count(1) FILTER (where dequeued_at is not null AND finished_at is null AND dequeued_at < now() - INTERVAL '3 hours' AND dequeued_at > now() - INTERVAL '24 hours') as timed_out
from testinstance`

	row := db.QueryRow(query)

	var pendingRuns, running, timedOut int64
	if err := row.Scan(&pendingRuns, &running, &timedOut); err != nil {
		return -1, -1, -1, errors.Wrap(err, "failed to scan")
	}

	return pendingRuns, running, timedOut, nil
}

func AddNodeJoinCommand(id string, primaryJoin string, secondaryJoin string) error {
	db := persistence.MustGetPGSession()
	query := `update testinstance set primary_join_command = $2, secondary_join_command = $3 where id = $1`

	if _, err := db.Exec(query, id, primaryJoin, secondaryJoin); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func GetNodeJoinCommand(id string) (string, string, error) {
	db := persistence.MustGetPGSession()

	query := `select primary_join_command, secondary_join_command from testinstance where id = $1`
	row := db.QueryRow(query, id)

	var primaryJoin, secondaryJoin sql.NullString
	if err := row.Scan(&primaryJoin, &secondaryJoin); err != nil {
		return "", "", errors.Wrap(err, "failed to scan")
	}

	return primaryJoin.String, secondaryJoin.String, nil
}

func GetRunStatus(id string) (bool, error) {
	db := persistence.MustGetPGSession()

	query := `select is_success from testinstance where id = $1`
	row := db.QueryRow(query, id)

	var is_success bool
	if err := row.Scan(&is_success); err != nil {
		return false, errors.Wrap(err, "failed to scan")
	}

	return is_success, nil
}

func AddClusterNode(instanceId string, id string, nodeType string, status string) error {
	db := persistence.MustGetPGSession()
	query := `insert into clusternode (testinstance_id, id, node_type, status, created_at) values ($1, $2, $3, $4, $5)`

	if _, err := db.Exec(query, instanceId, id, nodeType, status, time.Now()); err != nil {
		return errors.Wrap(err, "failed to insert")
	}

	return nil
}

func UpdateNodeStatus(id string, status string) error {
	db := persistence.MustGetPGSession()
	query := `update clusternode set status = $2 where id = $1`

	if _, err := db.Exec(query, id, status); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func NodeLogs(id string, logs string) error {
	db := persistence.MustGetPGSession()

	query := `update clusternode set output = $2 where id = $1`

	if _, err := db.Exec(query, id, logs); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func GetNodeLogs(id string) (string, error) {
	db := persistence.MustGetPGSession()

	query := `select output from clusternode where id = $1`
	row := db.QueryRow(query, id)

	var logs sql.NullString
	if err := row.Scan(&logs); err != nil {
		return "", errors.Wrap(err, "failed to scan")
	}

	return logs.String, nil
}

func GetNodeStatus(id string) (string, error) {
	db := persistence.MustGetPGSession()

	query := `select status from clusternode where id = $1`
	row := db.QueryRow(query, id)

	var status sql.NullString
	if err := row.Scan(&status); err != nil {
		return "", errors.Wrap(err, "failed to scan")
	}

	return status.String, nil
}
