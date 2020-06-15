import * as React from "react";
import RunTable from "../views/RunTable";
import Loader from "../views/Loader";

import "../../assets/scss/components/Home.scss";

class Home extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      isLoading: true,
    }
  }

  componentDidMount() {
    this.setState({ isLoading: true });

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
      <div className="HomeContainer">
        <p className="title">kURL Test Runs</p>
        <RunTable runs={this.state.runs} />
      </div>
    );
  }
}

export default Home;
