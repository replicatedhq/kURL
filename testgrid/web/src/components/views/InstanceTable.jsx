import * as React from "react";

import * as Modal from "react-modal";
import MonacoEditor from "react-monaco-editor";
import Loader from "./Loader";

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
    };
  }

  getOSArray = () => {
    const osMap = {};
    for (let i = 0; i < this.props.instances.length; i++) {
      const instance = this.props.instances[i];
      osMap[`${instance.osName}-${instance.osVersion}`] = true;
    }
    return Object.keys(osMap);
  }

  hideInstallerModal = () => {
    this.setState({ showInstallerModal: false });
  }

  viewInstanceInstaller = instance => {
    this.setState({
      selectedInstance: instance,
      showInstallerModal: true,
    });
  }

  hideLogsModal = () => {
    this.setState({ showLogsModal: false });
  }

  viewInstanceLogs = instance => {
    this.setState({ loadingLogs: true, showLogsModal: true, selectedInstance: instance });

    fetch(`${window.env.API_ENDPOINT}/instance/${instance.id}/logs`)
      .then((res) => {
        return res.json()
      })
      .then((responseJson) => {
        this.setState({
          instanceLogs: responseJson.logs,
          loadingLogs: false,
        })
      })
      .catch((err) => {
        console.error(err);
        this.setState({ loadingLogs: false });
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

  render() {
    const osArray = this.getOSArray();
    const rows = this.props.instances.map((instance) => {
      return (
        <tr key={instance.id}>
          <td><span className="url" onClick={() => this.viewInstanceInstaller(instance)}>{instance.kurlURL}</span></td>
          {osArray.map(key => {
            if (key == `${instance.osName}-${instance.osVersion}`) {
              return (
                <td
                  key={`${instance.id}-${key}`}
                  className={`${instance.isSuccess ? "passed" : "failed"}`}
                >
                  <div className="InstanceStatus-wrapper">
                    {instance.isSuccess ? "Passed" : "Failed"}
                    <button type="button" className="btn secondary" onClick={() => this.viewInstanceLogs(instance)}>Logs</button>
                  </div>
                </td>
              );
            }
            return <td key={`${instance.id}-${key}`}>-</td>;
          })}
        </tr>
      )
    })

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
          className="Modal InstanceModal"
        >
          <div className="Modal-header">
            <p>Installer for kURL URL: <a href={this.state.selectedInstance?.kurlURL} target="_blank">{this.state.selectedInstance?.kurlURL}</a></p>
          </div>
          <div className="Modal-body InstanceModal-body">
            <div className="MonacoEditor-wrapper">
              <MonacoEditor
                language="json"
                value={this.prettifyJSON(this.state.selectedInstance?.kurlYaml)}
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
            <div className="InstanceModal-actions">
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
          className="Modal InstanceModal"
        >
          <div className="Modal-header">
            <p>Logs for kURL URL: <a href={this.state.selectedInstance?.kurlURL} target="_blank">{this.state.selectedInstance?.kurlURL}</a> <span className={`${this.state.selectedInstance?.isSuccess ? "text-passed" : "text-failed"}`}>({this.state.selectedInstance?.isSuccess ? "Passed" : "Failed"})</span></p>
          </div>
          {this.state.loadingLogs ? 
            <Loader />
            :
            <div className="Modal-body InstanceModal-body">
              <div className="MonacoEditor-wrapper">
                <MonacoEditor
                  language="json"
                  value={this.state.instanceLogs}
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
              <div className="InstanceModal-actions">
                <button type="button" className="btn primary" onClick={this.hideLogsModal}>Ok, got it!</button>
              </div>
            </div>
          }
        </Modal>
      </div>
    );
  }
}

