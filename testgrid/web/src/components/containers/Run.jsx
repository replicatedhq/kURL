import * as React from "react";
import InstanceTable from "../views/InstanceTable";
import Loader from "../views/Loader";
import Pager from "../views/Pager";

import "../../assets/scss/components/Run.scss";

class Run extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      instances: [],
      isLoading: true,
      currentPage: 0,
      pageSize: 20,
      totalCount: 0,
    }
  }

  componentDidMount() {
    this.loadRunInstances();
  }

  onGotoPage = (page, event) => {
    event.preventDefault();
    this.setState({ currentPage: page });
    this.loadRunInstances(page, this.state.pageSize);
  }

  loadRunInstances = (currentPage = 0, pageSize = 20) => {
    this.setState({ isLoading: true });

    fetch(`${window.env.API_ENDPOINT}/run/${this.props.match.params.runId}?currentPage=${currentPage}&pageSize=${pageSize}`)
      .then((res) => {
        return res.json()
      })
      .then((resJson) => {
        this.setState({
          instances: resJson.instances,
          totalCount: resJson.total,
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
        <InstanceTable runId={this.props.match.params.runId} instances={this.state.instances} />
        <Pager
          pagerType="instances"
          currentPage={parseInt(this.state.currentPage) || 0}
          pageSize={this.state.pageSize}
          totalCount={this.state.totalCount}
          loading={false}
          currentPageLength={this.state.instances.length}
          goToPage={this.onGotoPage}
        />
      </div>
    );
  }
}

export default Run;
