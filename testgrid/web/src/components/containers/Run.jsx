import * as React from "react";
import "../../assets/css/components/Home.css";
import RunTable from "../views/RunTable";

class Run extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      isLoading: true,
    }
  }

  componentDidMount() {
    fetch(`${window.env.API_ENDPOINT}/run/${this.props.match.params.runId}`)
    .then((res) => {
      return res.json()
    })
    .then((runs) => {
      this.setState({
        runs: runs.runs,
        isLoading: false,
      })
    })
    .catch((err) => {
      console.error(err);
    })
  }

  render() {
    if (this.state.isLoading) {
      return (
        <div>loading...</div>
      );
    }

    return (
      <div>
        <h1>kURL Test Run {`${this.props.match.params.runId}`}</h1>
      </div>
    );
  }
}

export default Run;
