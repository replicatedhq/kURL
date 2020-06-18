package testinstance

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance/types"
	"gopkg.in/yaml.v2"
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

func Create(id string, refID, kurlYAML string, kurlURL string, osName string, osVersion string, osImage string) error {
	pg := persistence.MustGetPGSession()

	query := `insert into testinstance (id, enqueued_at, testrun_ref, kurl_yaml, kurl_url, os_name, os_version, os_image)
values ($1, $2, $3, $4, $5, $6, $7, $8)`
	if _, err := pg.Exec(query, id, time.Now(), refID, kurlYAML, kurlURL, osName, osVersion, osImage); err != nil {
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
limit 1) returning id, dequeued_at, testrun_ref, kurl_yaml, kurl_url, os_name, os_version, os_image
) select id, testrun_ref, kurl_yaml, kurl_url, os_name, os_version, os_image from updated`

	row := db.QueryRow(query)

	testInstance := types.TestInstance{}
	if err := row.Scan(&testInstance.ID,
		&testInstance.RefID,
		&testInstance.KurlYAML,
		&testInstance.KurlURL,
		&testInstance.OSName,
		&testInstance.OSVersion,
		&testInstance.OSImage,
	); err != nil {
		return nil, errors.Wrap(err, "failed to query test instance")
	}

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

func Finish(id string) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set finished_at = now() where id = $1 and finished_at is null`

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

func SetInstanceSuccess(id string, isSuccess bool) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set is_success = $1, finished_at = now() where id = $2`

	if _, err := db.Exec(query, isSuccess, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

// List returns a list of test instances.
// Note: pagination (limit and offset) are applied to instances with distinct kurl URLs (instances with same kurl URL count as 1)
func List(refID string, limit int, offset int, addons map[string]string) ([]types.TestInstance, error) {
	db := persistence.MustGetPGSession()

	query := `SELECT ti.id, ti.kurl_yaml, ti.kurl_url, ti.os_name, ti.os_version, ti.os_image, ti.enqueued_at, ti.dequeued_at, ti.started_at, ti.finished_at, ti.is_success
FROM testinstance ti
LEFT JOIN (
	SELECT kurl_url, row_number() OVER (ORDER BY kurl_url) row_num
	FROM testinstance
	GROUP BY kurl_url
) AS x ON x.kurl_url = ti.kurl_url
WHERE ti.testrun_ref = $1 AND x.row_num > $2`

	// pagination
	args := []interface{}{refID, offset}
	if limit > 0 {
		query += ` AND x.row_num <= $3`
		args = append(args, offset+limit)
	}

	// filter addons
	for addon, version := range addons {
		if version == "" {
			continue
		}
		query += fmt.Sprintf(` AND kurl_yaml::jsonb @> '{"spec":{"%s":{"version": "%s"}}}'::jsonb`, addon, version)
	}

	query += ` ORDER BY kurl_url, os_name, os_version`

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
		var isSuccess sql.NullBool

		if err := rows.Scan(
			&testInstance.ID,
			&testInstance.KurlYAML,
			&testInstance.KurlURL,
			&testInstance.OSName,
			&testInstance.OSVersion,
			&testInstance.OSImage,
			&enqueuedAt,
			&dequeuedAt,
			&startedAt,
			&finishedAt,
			&isSuccess,
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
		if isSuccess.Valid {
			testInstance.IsSuccess = isSuccess.Bool
		}

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
