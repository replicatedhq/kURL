import * as React from "react";
import InstanceTable from "../views/InstanceTable";
import Loader from "../views/Loader";

import "../../assets/scss/components/Run.scss";

class Run extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      instances: [],
      isLoading: true,
    }
  }

  componentDidMount() {
    this.setState({ isLoading: true });

    fetch(`${window.env.API_ENDPOINT}/run/${this.props.match.params.runId}`)
      .then((res) => {
        return res.json()
      })
      .then((resJson) => {
        this.setState({
          instances: resJson.instances,
          isLoading: false,
        })
      })
      .catch((err) => {
        console.error(err);
        this.setState({ isLoading: false });
      });
  }

  render() {
    if (this.state.isLoading) {
      return (
        <div style={{ marginTop: 24 }}>
          <Loader />
        </div>
      );
    }

    return (
      <div className="RunContainer">
        <p className="title">kURL Test Run: {`${this.props.match.params.runId}`}</p>
        <InstanceTable instances={this.state.instances} />
      </div>
    );
  }
}

export default Run;
