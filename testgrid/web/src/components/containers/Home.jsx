import * as React from "react";
import "../../assets/css/components/Home.css";
import RunTable from "../views/RunTable";

class Home extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      isLoading: true,
    }
  }

  componentDidMount() {
    fetch(`${window.env.API_ENDPOINT}/runs`)
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
        <h1>kURL Test Runs</h1>
        <RunTable runs={this.state.runs} />
      </div>
    );
  }
}

export default Home;
