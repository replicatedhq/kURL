package testrun

import (
	"time"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/testrun/types"
)

func TryGet(id string) (*types.TestRun, error) {
	pg := persistence.MustGetPGSession()

	query := `select count(1) from testrun where ref = $1`
	row := pg.QueryRow(query, id)

	count := 0
	if err := row.Scan(&count); err != nil {
		return nil, errors.Wrap(err, "failed to scan count")
	}

	if count == 0 {
		return nil, nil
	}

	query = `select ref, created_at from testrun where ref = $1`
	row = pg.QueryRow(query, id)

	testRun := types.TestRun{}

	if err := row.Scan(&testRun.ID, &testRun.CreatedAt); err != nil {
		return nil, errors.Wrap(err, "failed to scan")
	}

	return &testRun, nil
}

func Delete(id string) error {
	pg := persistence.MustGetPGSession()

	query := `delete from testrun where ref = $1`
	if _, err := pg.Exec(query, id); err != nil {
		return errors.Wrap(err, "failed to delete")
	}

	query = `delete from testinstance where testrun_ref = $1`
	if _, err := pg.Exec(query, id); err != nil {
		return errors.Wrap(err, "failed to delete")
	}

	return nil
}

func Create(id string) error {
	pg := persistence.MustGetPGSession()

	query := `insert into testrun (ref, created_at) values ($1, $2)`
	if _, err := pg.Exec(query, id, time.Now()); err != nil {
		return errors.Wrap(err, "failed to insert")
	}

	return nil
}

func List(limit int, offset int, searchRef string) ([]types.TestRun, error) {
	pg := persistence.MustGetPGSession()

	query := `
select 
	ref,
	created_at,
	COUNT(id) as total,
	COUNT(id) FILTER (WHERE is_success AND (NOT is_unsupported OR is_unsupported IS NULL)) AS successes,
	COUNT(id) FILTER (WHERE NOT is_success AND (NOT is_unsupported OR is_unsupported IS NULL) AND finished_at IS NOT NULL) as failures,
	MAX(started_at) as latest_started,
	MAX(finished_at) as latest_completion,
	COUNT(id) FILTER (WHERE finished_at IS NULL) as pending_runs
from testrun 
	left join testinstance on testrun.ref=testinstance.testrun_ref
where
	lower(ref) like '%' || $1 || '%'
group by 
	ref 
order by 
	created_at desc
`

	// pagination
	args := []interface{}{searchRef}
	if limit > 0 {
		query += ` limit $2`
		args = append(args, limit)
	}
	if offset > 0 {
		query += ` offset $3`
		args = append(args, offset)
	}

	rows, err := pg.Query(query, args...)
	if err != nil {
		return nil, errors.Wrap(err, "failed to list runs")
	}

	runs := []types.TestRun{}
	for rows.Next() {
		run := types.TestRun{}

		if err := rows.Scan(&run.ID, &run.CreatedAt, &run.TotalRuns, &run.SuccessCount, &run.FailureCount, &run.LastStart, &run.LastResponse, &run.PendingRuns); err != nil {
			return nil, errors.Wrap(err, "failed to scan run")
		}

		runs = append(runs, run)
	}

	return runs, nil
}

func Total(searchRef string) (int, error) {
	db := persistence.MustGetPGSession()

	query := `select count(1) as total from testrun where lower(ref) like '%' || $1 || '%'`
	row := db.QueryRow(query, searchRef)

	var total int
	if err := row.Scan(&total); err != nil {
		return -1, errors.Wrap(err, "failed to scan")
	}

	return total, nil
}

func GetRunByID(id string) (types.TestRunInstance, error) {
	db := persistence.MustGetPGSession()
	query := `SELECT ti.id, ti.test_name, ti.kurl_yaml, ti.kurl_url, ti.kurl_flags, ti.upgrade_yaml, ti.upgrade_url, ti.supportbundle_yaml, ti.post_install_script, ti.post_upgrade_script, ti.os_name, ti.os_version, ti.os_image, ti.enqueued_at, ti.dequeued_at, ti.started_at, ti.finished_at, ti.is_success, ti.failure_reason, ti.is_unsupported, ti.num_primary_nodes, ti.num_secondary_nodes, ti.memory, ti.cpu
FROM testinstance ti
WHERE ti.id = $1`
	row := db.QueryRow(query, id)
	run := types.TestRunInstance{}
	if err := row.Scan(&run.ID, &run.TestName, &run.KurlYAML, &run.KurlURL, &run.KurlFlags, &run.UpgradeYAML, &run.UpgradeURL, &run.SupportbundleYAML, &run.PostInstallScript, &run.PostUpgradeScript, &run.OSName, &run.OSVersion, &run.OSImage, &run.EnqueuedAt, &run.DequeuedAt, &run.StartedAt, &run.FinishedAt, &run.IsSuccess, &run.FailureReason, &run.IsUnsupported, &run.NumPrimaryNodes, &run.NumSecondaryNodes, &run.Memory, &run.CPU); err != nil {
		return run, errors.Wrap(err, "failed to scan")
	}

	return run, nil
}
