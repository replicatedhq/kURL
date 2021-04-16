import * as React from "react";
import * as moment from "moment";

import { Link } from "react-router-dom";

import "../../assets/scss/components/RunTable.scss";

export default class RunTable extends React.Component {
    render() {
        const rows = this.props.runs.map((run) => {
            return (
                <tr key={run.id}>
                    <td><Link to={`/run/${run.id}`}>{run.id}</Link></td>
                    <td>{moment(run.created_at).format("MMM D, YYYY h:mma")}</td>
                    <td>{run.last_start && moment(run.last_start).format("MMM D, YYYY h:mma")}</td>
                    <td>{run.last_response && moment(run.last_response).format("MMM D, YYYY h:mma")}</td>
                    <td>{`${run.success_count}`}</td>
                    <td>{`${run.failure_count}`}</td>
                    <td>{`${run.pending_runs}`}</td>
                </tr>
            )
        })
        return (
            <table>
                <thead>
                    <tr>
                        <th>kURL Ref</th>
                        <th>Run Started At</th>
                        <th>Last Instance Started At</th>
                        <th>Last Instance Completed At</th>
                        <th>Successes</th>
                        <th>Failures</th>
                        <th>Pending</th>
                    </tr>
                </thead>
                <tbody>
                    {rows}
                </tbody>
            </table>
        );
    }
}

