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

func FinishWithLogs(id string, logs []byte) error {
	db := persistence.MustGetPGSession()

	query := `update testinstance set finished_at = now(), output = $1 
where id = $2`

	if _, err := db.Exec(query, logs, id); err != nil {
		return errors.Wrap(err, "failed to update")
	}

	return nil
}

func List(refID string, limit int, offset int, addons map[string]string) ([]types.TestInstance, error) {
	db := persistence.MustGetPGSession()

	query := `select id, testrun_ref, kurl_yaml, kurl_url, os_name, os_version, os_image, enqueued_at, dequeued_at, started_at, finished_at, is_success
from testinstance where testrun_ref = $1`

	// filter addons
	for addon, version := range addons {
		if version == "" {
			continue
		}
		query += fmt.Sprintf(` and kurl_yaml::jsonb @> '{"spec":{"%s":{"version": "%s"}}}'::jsonb`, addon, version)
	}

	query += ` order by os_name, os_version, kurl_url`

	// pagination
	args := []interface{}{refID}
	if limit > 0 {
		query += ` limit $2`
		args = append(args, limit)
	}
	if offset > 0 {
		query += ` offset $3`
		args = append(args, offset)
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
		var isSuccess sql.NullBool

		if err := rows.Scan(
			&testInstance.ID,
			&testInstance.RefID,
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

	query := `select count(1) as total from testinstance where testrun_ref = $1`

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
