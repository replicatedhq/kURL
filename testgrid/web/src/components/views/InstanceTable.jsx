import * as React from "react";
import { useState, useEffect, useRef } from "react";
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom';

import * as Modal from "react-modal";
import * as find from "lodash/find";
import * as startCase from "lodash/startCase";
import * as parseAnsi from "parse-ansi";

import MonacoEditor from "react-monaco-editor";
import AceEditor from "react-ace";

import Loader from "../shared/Loader";

import "../../assets/scss/components/InstanceTable.scss";

import { getNodeLogs } from "./dataFetchers";

const InstanceTable = (props) => {
  const [searchParams] = useSearchParams();
  const location = useLocation();
  const navigate = useNavigate();

  const [selectedInstance, setSelectedInstance] = useState(null);
  const [selectedNode, setSelectedNode] = useState(null);
  const [instanceLogs, setInstanceLogs] = useState("");
  const [sonobuoyResults, setSonobuoyResults] = useState("");
  const [activeMarkers, setActiveMarkers] = useState([]);
  const [showInstallerModal, setShowInstallerModal] = useState(false);
  const [showLogsModal, setShowLogsModal] = useState(false);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [showSonobuoyResultsModal, setShowSonobuoyResultsModal] = useState(false);
  const [loadingSonobuoyResults, setLoadingSonobuoyResults] = useState(false);
  const [showUpgradeYaml, setShowUpgradeYaml] = useState(false);
  const [showSupportbundleYaml, setShowSupportbundleYaml] = useState(false);
  const [showPostInstallScript, setShowPostInstallScript] = useState(false);
  const [showPostUpgradeScript, setShowPostUpgradeScript] = useState(false);

  const logsAceEditor = useRef();

  useEffect(() => {
    if (searchParams.get("kurlLogsInstanceId") && searchParams.get('nodeId')) {
      const instance = findInstanceInMap(searchParams.get("kurlLogsInstanceId"));
      if (instance) {
        viewNodeLogs(searchParams.get('nodeId'), instance);
      }
    } else if(searchParams.get("kurlLogsInstanceId")) {
      const instance = findInstanceInMap(searchParams.get("kurlLogsInstanceId"));
      viewInstanceLogs(instance);
    } else if (searchParams.get("sonobuoyResultsInstanceId")) {
      const instance = findInstanceInMap(searchParams.get("sonobuoyResultsInstanceId"));
      viewInstanceSonobuoyResults(instance);
    }
  }, []);

  const findInstanceInMap = id => {
    const testIds = Object.keys(props.instancesMap);
    for (let k = 0; k < testIds.length; k++) {
      const testId = testIds[k];
      const testInstances = props.instancesMap[testId];
      for (let i = 0; i < testInstances.length; i++) {
        const instance = testInstances[i];
        if (instance.id === id) {
          return instance;
        }
      }
    }
    return null;
  }

  const getOSArray = instancesMap => {
    const osMap = {};
    Object.keys(instancesMap).forEach(testId => {
      instancesMap[testId].forEach(instance => {
        osMap[`${instance.osName}-${instance.osVersion}`] = true;
      });
    });
    return Object.keys(osMap);
  }

  const hideInstallerModal = () => {
    setShowInstallerModal(false);
  }

  const viewInstanceInstaller = instance => {
    setSelectedInstance(instance);
    setShowInstallerModal(true);
    setShowUpgradeYaml(false);
    setShowSupportbundleYaml(false);
    setShowPostInstallScript(false);
    setShowPostUpgradeScript(false);
  }

  const viewUpgradeInstaller = instance => {
    viewInstanceInstaller(instance);
    setShowUpgradeYaml(true);
  }

  const viewSupportbundleYaml = instance => {
    viewInstanceInstaller(instance);
    setShowSupportbundleYaml(true);
  }

  const viewPostInstallScript = instance => {
    viewInstanceInstaller(instance);
    setShowPostInstallScript(true);
  }

  const viewPostUpgradeScript = instance => {
    viewInstanceInstaller(instance);
    setShowPostUpgradeScript(true);
  }

  const hideLogsModal = () => {
    setShowLogsModal(false);
    setActiveMarkers([]);

    searchParams.delete("kurlLogsInstanceId");
    searchParams.delete("nodeId");

    navigate({
      pathname: location.pathname,
      search: searchParams.toString(),
      hash: "",
    }, {replace: true});
  }

  const hideSonobuoyResultsModal = () => {
    setShowSonobuoyResultsModal(false);
    setActiveMarkers([]);

    searchParams.delete("sonobuoyResultsInstanceId");

    navigate({
      pathname: location.pathname,
      search: searchParams.toString(),
      hash: "",
    }, {replace: true});
  }

  const viewInstanceLogs = instance => {
    searchParams.set("kurlLogsInstanceId", instance.id);
    searchParams.delete("nodeId");
    searchParams.delete("sonobuoyResultsInstanceId");

    navigate({
      pathname: location.pathname,
      search: searchParams.toString(),
      hash: location.hash,
    }, {replace: true});

    setLoadingLogs(true);
    setSelectedInstance(instance);
    setShowLogsModal(true);

    fetch(`${window.env.API_ENDPOINT}/instance/${instance.id}/logs`)
      .then((res) => {
        return res.json()
      })
      .then((responseJson) => {
        setLoadingLogs(false);
        setInstanceLogs(responseJson.logs);

        if (location?.hash) {
          setTimeout(() => {
            const selectedLine = parseInt(location.hash.substring(2));
            goToLineInEditor(logsAceEditor, selectedLine);
          }, 1000);
        }
      })
      .catch((err) => {
        console.error(err);
        setLoadingLogs(false);
      });
  }

  const viewNodeLogs = (nodeId, instance) => {
    searchParams.set("kurlLogsInstanceId", instance.id);
    searchParams.set("nodeId", nodeId);
    searchParams.delete("sonobuoyResultsInstanceId");

    navigate({
      pathname: location.pathname,
      search: searchParams.toString(),
      hash: location.hash,
    }, {replace: true});

    setLoadingLogs(true);
    setSelectedInstance(instance);
    setSelectedNode(nodeId);
    setShowLogsModal(true);

    getNodeLogs(nodeId).then(logs => {
      setLoadingLogs(false);
      setInstanceLogs(logs.data.logs);

      if (location?.hash) {
        setTimeout(() => {
          const selectedLine = parseInt(location.hash.substring(2));
          goToLineInEditor(logsAceEditor, selectedLine);
        }, 1000);
      }
    });
  }

  const viewInstanceSonobuoyResults = instance => {
    searchParams.set("sonobuoyResultsInstanceId", instance.id);
    searchParams.delete("kurlLogsInstanceId");
    searchParams.delete("nodeId");

    navigate({
      pathname: location.pathname,
      search: searchParams.toString(),
      hash: location.hash,
    }, {replace: true});

    setShowSonobuoyResultsModal(true);
    setLoadingSonobuoyResults(true);
    setSelectedInstance(instance);

    fetch(`${window.env.API_ENDPOINT}/instance/${instance.id}/sonobuoy`)
      .then((res) => {
        return res.json()
      })
      .then((responseJson) => {
        setLoadingSonobuoyResults(false);
        setSonobuoyResults(responseJson.results);
      })
      .catch((err) => {
        console.error(err);
        setLoadingSonobuoyResults(false);
      });
  }

  const prettifyJSON = value => {
    if (!value) {
      return "";
    }
    try {
      return JSON.stringify(JSON.parse(value), null, 4);
    } catch(err) {
      console.log(err);
      return "";
    }
  }

  const getInstanceStatus = instance => {
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

  const getInstanceFailureReason = instance => {
    if (!instance || !instance.failureReason) {
      return "";
    }
    return startCase(instance.failureReason);
  }

  const goToLineInEditor = (editorRef, line) => {
    editorRef?.current?.editor?.gotoLine(line);
  }

  const onSelectionChange = editorRef => {
    const column = editorRef?.current?.editor?.selection?.anchor.column;
    const row = editorRef?.current?.editor?.selection?.anchor.row;
    if (column === 0) {
      const activeMarkers = [{
        startRow: row - 1,
        endRow: row,
        className: "active-highlight",
        type: "background"
      }];
      setActiveMarkers(activeMarkers);

      navigate({
        pathname: location.pathname,
        search: searchParams.toString(),
        hash: `#L${row}`,
      }, {replace: true});
    }
  }

  const osArray = getOSArray(props.instancesMap);
  const rows = Object.keys(props.instancesMap).map((testId) => {
    const testInstance = props.instancesMap[testId];
    return (
      <tr key={testId}>
        <td><strong>{testInstance[0].testName}</strong></td>
        <td>
          <div className="url" onClick={() => viewInstanceInstaller(testInstance[0])}>{testInstance[0].kurlUrl}</div>
          {testInstance[0].kurlFlags &&
            <div>
              <span>{' Flags: '}</span>
              <span>{testInstance[0].kurlFlags}</span>
            </div>
            }
          {testInstance[0].upgradeUrl &&
            <div>
              <span>{' -> '}</span>
              <span className="url" onClick={() => viewUpgradeInstaller(testInstance[0])}>{testInstance[0].upgradeUrl}</span>
            </div>
            }
          {testInstance[0].supportbundleYaml &&
            <div>
              <br/>
              <span className="url" onClick={() => viewSupportbundleYaml(testInstance[0])}>Support Bundle YAML</span>
            </div>
            }
          {testInstance[0].postInstallScript &&
            <div>
              <br/>
              <span className="url" onClick={() => viewPostInstallScript(testInstance[0])}>Post-Install Script</span>
            </div>
            }
          {testInstance[0].postUpgradeScript &&
            <div>
              <br/>
              <span className="url" onClick={() => viewPostUpgradeScript(testInstance[0])}>Post-Upgrade Script</span>
            </div>
            }
        </td>
        {osArray.map(osKey => {
          const instance = find(testInstance, i => (osKey == `${i.osName}-${i.osVersion}`));
          if (instance) {
            const status = getInstanceStatus(instance);
            const failureReason = getInstanceFailureReason(instance);
            const initialPrimaryId = instance.id+"-initialprimary";
            const secondaryNodes = []
            const primaryNodes = []
            for (let i = 0; i < instance.numSecondaryNodes ; i++) {
                let nodeId = `${instance.id}-secondary-${i}`
                secondaryNodes.push(<button  key={i} type="button" className="btn xsmall primary u-width--full u-marginBottom--5" onClick={() => viewNodeLogs(nodeId, instance)}>{"Logs Secondary-"+i+ " Node"}</button>)
            }
            for (let i = 1; i < instance.numPrimaryNodes; i++) {
              let nodeId = `${instance.id}-primary-${i}`
              primaryNodes.push(<button key={i} type="button" className="btn xsmall primary u-width--full u-marginBottom--5" onClick={() => viewNodeLogs(nodeId, instance)}>{"Logs primary-" + i + " Node"}</button>)
            }
            return (
              <td
                key={`${testId}-${osKey}-${instance.id}`}
                className={status}
              >
                <div className="flex flex1 alignItems--center">
                  <span className={`status-text ${status} flex1`}>{status}<br/><small>{failureReason}</small></span>
                  {(instance.startedAt && !instance.isUnsupported) &&
                    <div className="flex-column flex1 alignItems--flexEnd">

                      {instance.finishedAt &&
                        <button type="button" className="btn xsmall secondary blue u-width--full" onClick={() => viewInstanceSonobuoyResults(instance)}>Sonobuoy</button>
                      }
                    </div>
                  }
                </div>
                {(instance.startedAt && !instance.isUnsupported) &&
                <div className="flex flex1 alignItems--center cluster-node">
                  <div className="flex-column flex1 alignItems--flexEnd">
                    <button type="button" className="btn xsmall primary u-width--full u-marginBottom--5" onClick={() => viewNodeLogs(initialPrimaryId, instance)}>Logs Initialprimary Node</button>
                    {primaryNodes}
                    {secondaryNodes}
                  </div>
                </div>
                }
              </td>
            );
          }
          return <td key={`${testId}-${osKey}`}>-</td>;
        })}
      </tr>
    )
  });

  let editorContent = "";
  if (showUpgradeYaml) {
    editorContent = prettifyJSON(selectedInstance?.upgradeYaml)
  } else if (showSupportbundleYaml) {
    editorContent = prettifyJSON(selectedInstance?.supportbundleYaml);
  } else if (showPostInstallScript) {
    editorContent = selectedInstance?.postInstallScript;
  } else if (showPostUpgradeScript) {
    editorContent = selectedInstance?.postUpgradeScript;
  } else {
    editorContent = prettifyJSON(selectedInstance?.kurlYaml);
  }

  return (
    <div className="InstanceTableContainer">
      <table>
        <thead>
          <tr>
            <th>Test Name</th>
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
        isOpen={showInstallerModal}
        onRequestClose={hideInstallerModal}
        shouldReturnFocusAfterClose={false}
        contentLabel="View installer"
        ariaHideApp={false}
        className="Modal LargeSize flex-column u-height--threeQuarters"
      >
        <div className="Modal-header">
            <p>Installer for kURL URL: <a href={selectedInstance?.kurlUrl} target="_blank" rel="noreferrer">{selectedInstance?.kurlUrl}</a></p>
        </div>
        <div className="Modal-body flex1 flex-column">
          <div className="MonacoEditor-wrapper">
            <MonacoEditor
              language="json"
              value={editorContent}
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
            <button type="button" className="btn primary" onClick={hideInstallerModal}>Ok, got it!</button>
          </div>
        </div>
      </Modal>

      <Modal
        isOpen={showLogsModal}
        onRequestClose={hideLogsModal}
        shouldReturnFocusAfterClose={false}
        contentLabel="View logs"
        ariaHideApp={false}
        className="Modal XLargeSize flex-column u-height--fourFifths"
      >
        <div className="Modal-header">
          <p>
            <span>Logs for: </span>
            <a href={selectedInstance?.kurlUrl} target="_blank" rel="noreferrer">{selectedInstance?.kurlUrl}</a>
            <span> / </span>
            <span>{selectedInstance?.osName}-{selectedInstance?.osVersion} </span>
            <span className={`status-text ${getInstanceStatus(selectedInstance)}`}>node/{selectedNode}({getInstanceStatus(selectedInstance)})</span>
          </p>
        </div>
        {loadingLogs ?
          <Loader />
          :
          <div className="Modal-body flex1 flex-column">
            <div className="AceEditor-wrapper">
              <AceEditor
                ref={logsAceEditor}
                mode="text"
                theme="chrome"
                className="flex1 flex"
                readOnly={true}
                value={parseAnsi(instanceLogs).plainText}
                height="100%"
                width="100%"
                markers={activeMarkers}
                editorProps={{
                  $blockScrolling: Infinity,
                  useSoftTabs: true,
                  tabSize: 2,
                }}
                onSelectionChange={() => onSelectionChange(logsAceEditor)}
                setOptions={{
                  scrollPastEnd: false,
                  showGutter: true,
                }}
              />
            </div>
            <div className="u-marginTop--20">
              <button type="button" className="btn primary" onClick={hideLogsModal}>Ok, got it!</button>
            </div>
          </div>
        }
      </Modal>

      <Modal
        isOpen={showSonobuoyResultsModal}
        onRequestClose={hideSonobuoyResultsModal}
        shouldReturnFocusAfterClose={false}
        contentLabel="View logs"
        ariaHideApp={false}
        className="Modal XLargeSize flex-column u-height--fourFifths"
      >
        <div className="Modal-header">
          <p>
            <span>Sonobuoy Results for: </span>
            <a href={selectedInstance?.kurlUrl} target="_blank" rel="noreferrer">{selectedInstance?.kurlUrl}</a>
            <span> / </span>
            <span>{selectedInstance?.osName}-{selectedInstance?.osVersion} </span>
            <span className={`status-text ${getInstanceStatus(selectedInstance)}`}>({getInstanceStatus(selectedInstance)})</span>
          </p>
        </div>
        {loadingSonobuoyResults ?
          <Loader />
          :
          <div className="Modal-body flex1 flex-column">
            <div className="MonacoEditor-wrapper">
              <MonacoEditor
                value={sonobuoyResults}
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
              <button type="button" className="btn primary" onClick={hideSonobuoyResultsModal}>Ok, got it!</button>
            </div>
          </div>
        }
      </Modal>
    </div>
  );
}

export default InstanceTable;
