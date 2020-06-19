import * as React from "react";
import RunTable from "../views/RunTable";
import Loader from "../shared/Loader";
import Pager from "../shared/Pager";

import "../../assets/scss/components/Home.scss";

class Home extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      runs: [],
      currentPage: 0,
      pageSize: 20,
      totalCount: 0,
      isLoading: true,
      searchRef: "",
    }
  }

  componentDidMount() {
    this.loadRuns();
  }

  loadRuns = async (currentPage = 0, pageSize = 20) => {
    try {
      this.setState({ isLoading: true });

      const res = await fetch(`${window.env.API_ENDPOINT}/runs?currentPage=${currentPage}&pageSize=${pageSize}&searchRef=${this.state.searchRef}`);
      const resJson = await res.json();

      this.setState({
        runs: resJson.runs,
        totalCount: resJson.total,
        isLoading: false,
      });

      return true;
    } catch(err) {
      console.error(err);
      this.setState({ isLoading: false });
      return false;
    }
  }

  onGotoPage = (page, event) => {
    event.preventDefault();
    this.setState({ currentPage: page });
    this.loadRuns(page, this.state.pageSize);
  }

  searchRuns = async () => {
    const success = await this.loadRuns();
    if (success) {
      this.setState({ currentPage: 0 });
    }
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
        <p className="u-fontSize--jumbo2 u-fontWeight--bold u-color--tuna u-borderBottom--gray u-paddingBottom--small">kURL Test Runs</p>

        <div className="flex alignItems--center u-marginBottom--20">
          <input
            className="Input flex2 u-marginRight--20"
            type="text"
            placeholder="Search kURL ref"
            value={this.state.searchRef}
            onChange={e => this.setState({ searchRef: e.target.value })}
          />
          <button type="button" className="btn primary" onClick={this.searchRuns}>Search</button>
        </div>

        <RunTable runs={this.state.runs} />

        <Pager
          pagerType="runs"
          currentPage={parseInt(this.state.currentPage) || 0}
          pageSize={this.state.pageSize}
          totalCount={this.state.totalCount}
          loading={false}
          currentPageLength={this.state.runs.length}
          goToPage={this.onGotoPage}
        />
      </div>
    );
  }
}

export default Home;
