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
                </tr>
            )
        })
        return (
            <table>
                <thead>
                    <tr>
                        <th>kURL Ref</th>
                        <th>Run Started At</th>
                    </tr>
                </thead>
                <tbody>
                    {rows}
                </tbody>
            </table>
        );
    }
}

