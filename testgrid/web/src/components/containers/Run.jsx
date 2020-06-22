import * as React from "react";
import * as groupBy from "lodash/groupBy";
import * as queryString from "query-string";

import InstanceTable from "../views/InstanceTable";
import Loader from "../shared/Loader";
import Pager from "../shared/Pager";

import "../../assets/scss/components/Run.scss";

class Run extends React.Component {
  constructor(props) {
    super(props);

    let currentPage = 0, pageSize = 500;
    const params = queryString.parse(this.props.location.search);
    if (params.currentPage) {
      currentPage = parseInt(params.currentPage);
    }
    if (params.pageSize) {
      pageSize = parseInt(params.pageSize);
    }

    this.state = {
      instancesMap: {},
      isLoading: true,
      currentPage,
      pageSize,
      totalCount: 0,
      addons: {},
    };

    this.instancesTable = React.createRef();
  }

  async componentDidMount() {
    await this.loadRunInstances();
    await this.loadUniqueAddons();

    const params = queryString.parse(this.props.location.search);
    if (params.kurlLogsInstanceId) {
      const instance = this.findInstanceInMap(params.kurlLogsInstanceId);
      this.instancesTable?.current?.viewInstanceLogs(instance);
    } else if (params.sonobuoyResultsInstanceId) {
      const instance = this.findInstanceInMap(params.sonobuoyResultsInstanceId);
      this.instancesTable?.current?.viewInstanceSonobuoyResults(instance);
    }
  }

  findInstanceInMap = id => {
    const kurlURLs = Object.keys(this.state.instancesMap);
    for (let k = 0; k < kurlURLs.length; k++) {
      const kurlURL = kurlURLs[k];
      const kurlUrlInstances = this.state.instancesMap[kurlURL];
      for (let i = 0; i < kurlUrlInstances.length; i++) {
        const instance = kurlUrlInstances[i];
        if (instance.id === id) {
          return instance;
        }
      }
    }
    return null;
  }

  onGotoPage = (page, event) => {
    event.preventDefault();

    const searchParams = queryString.parse(this.props.location.search);
    if (page > 0) {
      searchParams.currentPage = `${page}`;
    } else if ("currentPage" in searchParams) {
      delete searchParams["currentPage"];
    }
    
    this.props.history.replace({
      pathname: this.props.location.pathname,
      search: queryString.stringify(searchParams),
    });

    this.setState({ currentPage: page });
    this.loadRunInstances(page, this.state.pageSize);
  }

  loadRunInstances = async (currentPage = this.state.currentPage, pageSize = this.state.pageSize) => {
    try {
      this.setState({ isLoading: true });

      const res = await fetch(`${window.env.API_ENDPOINT}/run/${this.props.match.params.runId}`, {
        method: "POST",
        body: JSON.stringify({
          currentPage,
          pageSize,
          addons: this.state.addons,
        })
      });
  
      const resJson = await res.json();
  
      this.setState({
        instancesMap: groupBy(resJson.instances, "kurlURL"),
        totalCount: resJson.total,
        isLoading: false,
      })

      return true;
    } catch(err) {
      console.error(err);
      this.setState({ isLoading: false });
      return false;
    }
  }

  loadUniqueAddons = async () => {
    try {
      this.setState({ isLoading: true });

      const res = await fetch(`${window.env.API_ENDPOINT}/run/${this.props.match.params.runId}/addons`);
      const resJson = await res.json();
  
      this.setState({
        addons: this.getAddonsMap(resJson.addons),
        isLoading: false,
      })
    } catch(err) {
      console.error(err);
      this.setState({ isLoading: false });
    }
  }

  getAddonsMap = addonsArr => {
    if (!addonsArr) {
      return {};
    }

    addonsArr.sort();

    const addons = {};
    for (let i = 0; i < addonsArr.length; i++) {
      const addon = addonsArr[i];
      addons[addon] = this.state.addons[addon];
    };

    return addons;
  }

  setAddonVersion = (addon, version) => {
    const addons = { ...this.state.addons };
    addons[addon] = version;
    this.setState({ addons });
  }

  searchAddons = async () => {
    const success = await this.loadRunInstances();
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
      <div className="RunContainer">
        <div className="flex alignItems--center u-borderBottom--gray u-marginBottom--20 u-paddingBottom--small">
          <div className="u-marginRight--20 u-cursor--pointer" onClick={() => this.props.history.push("/")}>
            <span className="arrow left u-marginRight--5"></span>
            <span className="u-color--astral">Runs</span>
          </div>
          <span className="u-fontSize--jumbo2 u-fontWeight--bold u-color--tuna">kURL Test Run: {`${this.props.match.params.runId}`}</span>
        </div>
        
        {/* Addons search */}
        <div className="u-width--threeQuarters u-marginBottom--20 u-borderAll--gray u-padding--row">
          <div className="flex flexWrap--wrap u-marginBottom--10" >
            {this.state.addons && Object.keys(this.state.addons).map(addon => (
              <div key={addon} className="flex u-marginBottom--10 alignItems--center u-width--fourth">
                <span className="flex1 u-marginRight--10 u-fontWeight--bold">{addon}</span>
                <input
                  className="Input flex2 u-marginRight--20"
                  type="text"
                  placeholder="Version"
                  value={this.state.addons[addon]}
                  onChange={e => this.setAddonVersion(addon, e.target.value)}
                />
              </div>
            ))}
          </div>
          <button type="button" className="btn primary" onClick={this.searchAddons}>Search</button>
        </div>

        <InstanceTable
          ref={this.instancesTable}
          instancesMap={this.state.instancesMap}
          history={this.props.history}
          location={this.props.location}
        />

        <Pager
          pagerType="instances"
          currentPage={parseInt(this.state.currentPage) || 0}
          pageSize={this.state.pageSize}
          totalCount={this.state.totalCount}
          loading={false}
          currentPageLength={Object.keys(this.state.instancesMap).length}
          goToPage={this.onGotoPage}
        />
      </div>
    );
  }
}

export default Run;
