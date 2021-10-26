import * as React from "react";

import * as Modal from "react-modal";
import * as find from "lodash/find";
import * as startCase from "lodash/startCase";
import * as parseAnsi from "parse-ansi";
import * as queryString from "query-string";

import MonacoEditor from "react-monaco-editor";
import AceEditor from "react-ace";

import Loader from "../shared/Loader";

import "../../assets/scss/components/InstanceTable.scss";

export default class InstanceTable extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      showInstallerModal: false,
      showLogsModal: false,
      selectedInstance: null,
      instanceLogs: "",
      loadingLogs: false,
      sonobuoyResults: "",
      showSonobuoyResultsModal: false,
      loadingSonobuoyResults: false,
      activeMarkers: [],
      showUpgradeYaml: false,
      showSupportbundleYaml: false,
    };
  }

  getOSArray = instancesMap => {
    const osMap = {};
    Object.keys(instancesMap).forEach(kurlURL => {
      instancesMap[kurlURL].forEach(instance => {
        osMap[`${instance.osName}-${instance.osVersion}`] = true;
      });
    });
    return Object.keys(osMap);
  }

  hideInstallerModal = () => {
    this.setState({ showInstallerModal: false });
  }

  viewInstanceInstaller = instance => {
    this.setState({
      selectedInstance: instance,
      showInstallerModal: true,
      showUpgradeYaml: false,
      showSupportbundleYaml: false,
    });
  }

  viewUpgradeInstaller = instance => {
    this.setState({
      selectedInstance: instance,
      showInstallerModal: true,
      showUpgradeYaml: true,
      showSupportbundleYaml: false,
    });
  }

  viewSupportbundleYaml = instance => {
    this.setState({
      selectedInstance: instance,
      showInstallerModal: true,
      showUpgradeYaml: false,
      showSupportbundleYaml: true,
    });
  }

  hideLogsModal = () => {
    this.setState({ showLogsModal: false, activeMarkers: [] });

    if (this.props.location) {
      const searchParams = queryString.parse(this.props.location?.search);
      if ("kurlLogsInstanceId" in searchParams) {
        delete searchParams["kurlLogsInstanceId"];
      }
      this.props.history?.replace({
        pathname: this.props.location?.pathname,
        search: queryString.stringify(searchParams),
        hash: "",
      });
    }
  }

  hideSonobuoyResultsModal = () => {
    this.setState({ showSonobuoyResultsModal: false, activeMarkers: [] });
    
    if (this.props.location) {
      const searchParams = queryString.parse(this.props.location?.search);
      if ("sonobuoyResultsInstanceId" in searchParams) {
        delete searchParams["sonobuoyResultsInstanceId"];
      }
      this.props.history?.replace({
        pathname: this.props.location?.pathname,
        search: queryString.stringify(searchParams),
        hash: "",
      });
    }
  }

  viewInstanceLogs = instance => {
    if (this.props.location) {
      const searchParams = queryString.parse(this.props.location?.search);
      searchParams.kurlLogsInstanceId = instance.id;

      this.props.history?.replace({
        pathname: this.props.location?.pathname,
        search: queryString.stringify(searchParams),
        hash: this.props.location?.hash,
      });
    }

    this.setState({ loadingLogs: true, showLogsModal: true, selectedInstance: instance });

    fetch(`${window.env.API_ENDPOINT}/instance/${instance.id}/logs`)
      .then((res) => {
        return res.json()
      })
      .then((responseJson) => {
        this.setState({
          instanceLogs: responseJson.logs,
          loadingLogs: false,
        }, () => {
          if (this.props.location?.hash !== "") {
            setTimeout(() => {
              const selectedLine = parseInt(this.props.location.hash.substring(2));
              this.goToLineInEditor(this.logsAceEditor, selectedLine);
            }, 200);
          }
        });
      })
      .catch((err) => {
        console.error(err);
        this.setState({ loadingLogs: false });
      });
  }

  viewInstanceSonobuoyResults = instance => {
    if (this.props.location) {
      const searchParams = queryString.parse(this.props.location?.search);
      searchParams.sonobuoyResultsInstanceId = instance.id;

      this.props.history?.replace({
        pathname: this.props.location?.pathname,
        search: queryString.stringify(searchParams),
        hash: this.props.location?.hash,
      });
    }

    this.setState({ loadingSonobuoyResults: true, showSonobuoyResultsModal: true, selectedInstance: instance });

    fetch(`${window.env.API_ENDPOINT}/instance/${instance.id}/sonobuoy`)
      .then((res) => {
        return res.json()
      })
      .then((responseJson) => {
        this.setState({
          sonobuoyResults: responseJson.results,
          loadingSonobuoyResults: false,
        });
      })
      .catch((err) => {
        console.error(err);
        this.setState({ loadingSonobuoyResults: false });
      });
  }

  prettifyJSON = value => {
    try {
      if (!value) {
        return "";
      }
      return JSON.stringify(JSON.parse(value), null, 4);
    } catch(err) {
      console.log(err);
      return "";
    }
  }

  getInstanceStatus = instance => {
    if (!instance) {
      return "";
    }
    if (instance.finishedAt) {
      if (instance.isUnsupported) {
        return "Unsupported";
      }
      return instance.isSuccess ? "Passed" : "Failed";
    }
    if (instance.startedAt) {
      return "Running";
    }
    if (instance.dequeuedAt) {
      return "Dequeued";
    }
    if (instance.enqueuedAt) {
      return "Enqueued";
    }
  }

  getInstanceFailureReason = instance => {
    if (!instance || !instance.failureReason) {
      return "";
    }
    return startCase(instance.failureReason);
  }

  goToLineInEditor = (editorRef, line) => {
    editorRef?.editor?.gotoLine(line);
    this.setState({ activeMarkers: [{
      startRow: line - 1,
      endRow: line,
      className: "active-highlight",
      type: "background"
    }] });
  }

  onSelectionChange = editorRef => {
    const column = editorRef?.editor?.selection?.anchor.column;
    const row = editorRef?.editor?.selection?.anchor.row;
    if (column === 0) {
      const activeMarkers = [{
        startRow: row - 1,
        endRow: row,
        className: "active-highlight",
        type: "background"
      }];
      this.setState({ activeMarkers });
      this.props.history?.replace({
        pathname: this.props.location?.pathname,
        search: this.props.location?.search,
        hash: `#L${row}`,
      });
    }
  }

  render() {
    const osArray = this.getOSArray(this.props.instancesMap);
    const rows = Object.keys(this.props.instancesMap).map(kurlURL => {
      return (
        <tr key={kurlURL}>
          <td>
            <span className="url" onClick={() => this.viewInstanceInstaller(this.props.instancesMap[kurlURL][0])}>{kurlURL}</span>
            {this.props.instancesMap[kurlURL][0].upgradeUrl &&
              <div>
                <span>{' -> '}</span>
                <span className="url" onClick={() => this.viewUpgradeInstaller(this.props.instancesMap[kurlURL][0])}>{this.props.instancesMap[kurlURL][0].upgradeUrl}</span>
              </div>
              }
            {this.props.instancesMap[kurlURL][0].supportbundleYAML &&
              <div>
                <br/>
                <span className="url" onClick={() => this.viewSupportbundleYaml(this.props.instancesMap[kurlURL][0])}>Support Bundle YAML</span>
              </div>
              }
          </td>
          {osArray.map(osKey => {
            const instance = find(this.props.instancesMap[kurlURL], i => (osKey == `${i.osName}-${i.osVersion}`));
            if (instance) {
              const status = this.getInstanceStatus(instance);
              const failureReason = this.getInstanceFailureReason(instance);
              return (
                <td
                  key={`${kurlURL}-${osKey}-${instance.id}`}
                  className={status}
                >
                  <div className="flex flex1 alignItems--center">
                    <span className={`status-text ${status} flex1`}>{status}<br/><small>{failureReason}</small></span>
                    {(instance.startedAt && !instance.isUnsupported) &&
                      <div className="flex-column flex1 alignItems--flexEnd">
                        <button type="button" className="btn xsmall primary u-width--full u-marginBottom--5" onClick={() => this.viewInstanceLogs(instance)}>kURL Logs</button>
                        {instance.finishedAt &&
                          <button type="button" className="btn xsmall secondary blue u-width--full" onClick={() => this.viewInstanceSonobuoyResults(instance)}>Sonobuoy</button>
                        }
                      </div>
                    }
                  </div>
                </td>
              );
            }
            return <td key={`${kurlURL}-${osKey}`}>-</td>;
          })}
        </tr>
      )
    });

    return (
      <div className="InstanceTableContainer">
        <table>
          <thead>
            <tr>
              <th>kURL URL</th>
              {osArray.map(key => (
                <th key={key}>{key}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows}
          </tbody>
        </table>

        <Modal
          isOpen={this.state.showInstallerModal}
          onRequestClose={this.hideInstallerModal}
          shouldReturnFocusAfterClose={false}
          contentLabel="View installer"
          ariaHideApp={false}
          className="Modal LargeSize flex-column u-height--threeQuarters"
        >
          <div className="Modal-header">
              <p>Installer for kURL URL: <a href={this.state.selectedInstance?.kurlURL} target="_blank" rel="noreferrer">{this.state.selectedInstance?.kurlURL}</a></p>
          </div>
          <div className="Modal-body flex1 flex-column">
            <div className="MonacoEditor-wrapper">
              <MonacoEditor
                language="json"
                value={
                  this.state.showUpgradeYaml ?
                    this.prettifyJSON(this.state.selectedInstance?.upgradeYaml) : (
                      this.state.showSupportbundleYaml ?
                        this.prettifyJSON(this.state.selectedInstance?.supportbundleYAML) :
                        this.prettifyJSON(this.state.selectedInstance?.kurlYaml)
                    )
                  }
                height="100%"
                width="100%"
                options={{
                  readOnly: true,
                  contextmenu: false,
                  minimap: {
                    enabled: false
                  },
                  scrollBeyondLastLine: false,
                }}
              />
            </div>
            <div className="u-marginTop--20">
              <button type="button" className="btn primary" onClick={this.hideInstallerModal}>Ok, got it!</button>
            </div>
          </div>
        </Modal>

        <Modal
          isOpen={this.state.showLogsModal}
          onRequestClose={this.hideLogsModal}
          shouldReturnFocusAfterClose={false}
          contentLabel="View logs"
          ariaHideApp={false}
          className="Modal XLargeSize flex-column u-height--fourFifths"
        >
          <div className="Modal-header">
              <p>Logs for: <a href={this.state.selectedInstance?.kurlURL} target="_blank" rel="noreferrer">{this.state.selectedInstance?.kurlURL}</a> / {this.state.selectedInstance?.osName}-{this.state.selectedInstance?.osVersion} <span className={`status-text ${this.getInstanceStatus(this.state.selectedInstance)}`}>({this.getInstanceStatus(this.state.selectedInstance)})</span></p>
          </div>
          {this.state.loadingLogs ? 
            <Loader />
            :
            <div className="Modal-body flex1 flex-column">
              <div className="AceEditor-wrapper">
                <AceEditor
                  ref={input => (this.logsAceEditor = input)}
                  mode="text"
                  theme="chrome"
                  className="flex1 flex"
                  readOnly={true}
                  value={parseAnsi(this.state.instanceLogs).plainText}
                  height="100%"
                  width="100%"
                  markers={this.state.activeMarkers}
                  editorProps={{
                    $blockScrolling: Infinity,
                    useSoftTabs: true,
                    tabSize: 2,
                  }}
                  onSelectionChange={() => this.onSelectionChange(this.logsAceEditor)}
                  setOptions={{
                    scrollPastEnd: false,
                    showGutter: true,
                  }}
                />
              </div>
              <div className="u-marginTop--20">
                <button type="button" className="btn primary" onClick={this.hideLogsModal}>Ok, got it!</button>
              </div>
            </div>
          }
        </Modal>

        <Modal
          isOpen={this.state.showSonobuoyResultsModal}
          onRequestClose={this.hideSonobuoyResultsModal}
          shouldReturnFocusAfterClose={false}
          contentLabel="View logs"
          ariaHideApp={false}
          className="Modal XLargeSize flex-column u-height--fourFifths"
        >
          <div className="Modal-header">
            <p>Sonobuoy Results for: <a href={this.state.selectedInstance?.kurlURL} target="_blank" rel="noreferrer">{this.state.selectedInstance?.kurlURL}</a> / {this.state.selectedInstance?.osName}-{this.state.selectedInstance?.osVersion} <span className={`status-text ${this.getInstanceStatus(this.state.selectedInstance)}`}>({this.getInstanceStatus(this.state.selectedInstance)})</span></p>
          </div>
          {this.state.loadingSonobuoyResults ? 
            <Loader />
            :
            <div className="Modal-body flex1 flex-column">
              <div className="MonacoEditor-wrapper">
                <MonacoEditor
                  value={this.state.sonobuoyResults}
                  height="100%"
                  width="100%"
                  options={{
                    readOnly: true,
                    contextmenu: false,
                    minimap: {
                      enabled: false
                    },
                    scrollBeyondLastLine: false,
                  }}
                />
              </div>
              <div className="u-marginTop--20">
                <button type="button" className="btn primary" onClick={this.hideSonobuoyResultsModal}>Ok, got it!</button>
              </div>
            </div>
          }
        </Modal>
      </div>
    );
  }
}

