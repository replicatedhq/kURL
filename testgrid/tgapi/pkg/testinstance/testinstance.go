package testinstance

import (
	"database/sql"
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testinstance/types"
)

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

func List(refID string, limit int, offset int) ([]types.TestInstance, error) {
	db := persistence.MustGetPGSession()

	query := `select id, kurl_yaml, kurl_url, os_name, os_version, os_image, started_at, finished_at, is_success
from testinstance where testrun_ref = $1 order by os_name, os_version, kurl_url`

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
			&startedAt,
			&finishedAt,
			&isSuccess,
		); err != nil {
			return nil, errors.Wrap(err, "failed to scan")
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

func Total(refID string) (int, error) {
	db := persistence.MustGetPGSession()

	query := `select count(1) as total from testinstance where testrun_ref = $1`
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
