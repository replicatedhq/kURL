import * as React from "react";
import { useState, useEffect } from "react";
import { useLocation, useNavigate, useSearchParams, useParams } from 'react-router-dom';
import * as groupBy from "lodash/groupBy";

import InstanceTable from "../views/InstanceTable";
import Loader from "../shared/Loader";
import Pager from "../shared/Pager";

import "../../assets/scss/components/Run.scss";

const Run = () => {
  const [searchParams] = useSearchParams();
  const params = useParams();
  const location = useLocation();
  const navigate = useNavigate();

  const [isLoading, setIsLoading] = useState(false);
  const [instancesMap, setInstancesMap] = useState({});
  const [addons, setAddons] = useState({});
  const [totalCount, setTotalCount] = useState(0);
  const [currentPage, doSetCurrentPage]  = useState(parseInt(searchParams.get("currentPage")) || 0);
  const [pageSize] = useState(parseInt(searchParams.get("pageSize")) || 1000);

  useEffect(() => {
    loadUniqueAddons();
  }, []);

  useEffect(() => {
    loadRunInstances();
  }, [currentPage, pageSize, addons]);

  const setCurrentPage = (page) => {
    doSetCurrentPage(page);
    navigate({
      pathname: location.pathname,
      search: searchParams.toString(),
    }, {replace: true});
  }

  const loadRunInstances = async () => {
    try {
      setIsLoading(true);

      const res = await fetch(`${window.env.API_ENDPOINT}/run/${params.runId}`, {
        method: "POST",
        body: JSON.stringify({
          currentPage,
          pageSize,
          addons: addons,
        })
      });

      const resJson = await res.json();

      setIsLoading(false);
      setInstancesMap(groupBy(resJson.instances, "testId"));
      setTotalCount(resJson.total);

      return true;
    } catch(err) {
      console.error(err);
      setIsLoading(false);
      return false;
    }
  }

  const loadUniqueAddons = async () => {
    try {
      setIsLoading(true);

      const res = await fetch(`${window.env.API_ENDPOINT}/run/${params.runId}/addons`);
      const resJson = await res.json();

      setIsLoading(false);
      setAddons(getAddonsMap(resJson.addons));
    } catch(err) {
      console.error(err);
      setIsLoading(false);
    }
  }

  const getAddonsMap = addonsArr => {
    if (!addonsArr) {
      return {};
    }

    addonsArr.sort();

    const nextAddons = {};
    for (let i = 0; i < addonsArr.length; i++) {
      const addon = addonsArr[i];
      nextAddons[addon] = addons[addon];
    }

    return nextAddons;
  }

  const setAddonVersion = (addon, version) => {
    const addons = { ...addons };
    addons[addon] = version;
    setAddons(addons);
  }

  const searchAddons = async () => {
    const success = await loadRunInstances();
    if (success) {
      setCurrentPage(0);
    }
  }

  if (isLoading) {
    return (
      <div style={{ marginTop: 24 }}>
        <Loader />
      </div>
    );
  }

  return (
    <div className="RunContainer">
      <div className="flex alignItems--center u-borderBottom--gray u-marginBottom--20 u-paddingBottom--small">
        <div className="u-marginRight--20 u-cursor--pointer" onClick={() => navigate("/")}>
          <span className="arrow left u-marginRight--5"></span>
          <span className="u-color--astral">Runs</span>
        </div>
        <span className="u-fontSize--jumbo2 u-fontWeight--bold u-color--tuna">kURL Test Run: {`${params.runId}`}</span>
      </div>

      {/* Addons search */}
      <div className="u-width--threeQuarters u-marginBottom--20 u-borderAll--gray u-padding--row">
        <div className="flex flexWrap--wrap u-marginBottom--10" >
          {addons && Object.keys(addons).map(addon => (
            <div key={addon} className="flex u-marginBottom--10 alignItems--center u-width--fourth">
              <span className="flex1 u-marginRight--10 u-fontWeight--bold">{addon}</span>
              <input
                className="Input flex2 u-marginRight--20"
                type="text"
                placeholder="Version"
                value={addons[addon]}
                onChange={e => setAddonVersion(addon, e.target.value)}
              />
            </div>
          ))}
        </div>
        <button type="button" className="btn primary" onClick={searchAddons}>Search</button>
      </div>

      <InstanceTable
        instancesMap={instancesMap}
      />

      <Pager
        pagerType="instances"
        currentPage={currentPage}
        pageSize={pageSize}
        totalCount={totalCount}
        loading={false}
        currentPageLength={Object.keys(instancesMap).length}
        goToPage={setCurrentPage}
      />
    </div>
  );
}

export default Run;
