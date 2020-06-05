import * as React from "react"

export default class RunTable extends React.Component {
    render() {
        const rows = this.props.runs.map((run) => {
            return (
                <tr key={run.id} style={{border: "1px solid #000", padding: "5px"}}>
                    <td style={{minWidth: "200px"}}><a href={`/run/${run.id}`}>{run.id}</a></td>
                    <td>{run.created_at}</td>
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

