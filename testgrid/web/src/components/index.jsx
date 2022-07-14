import * as React from "react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import ErrorBoundary from "./containers/ErrorBoundary";
import NotFound from "./shared/NotFound";
import Home from "./containers/Home";
import Run from "./containers/Run";
import Layout from "./shared/Layout";

import "../assets/scss/index.scss";

class Root extends React.Component {
  constructor(props) {
    super(props);
  }

  render() {
    return (
      <BrowserRouter>
        <ErrorBoundary>
          <Layout title={"kURL Test Grid"}>
            <Routes>
              <Route exact path="/" element={<Home />} />
              <Route exact path="/run/:runId" element={<Run />} />
              <Route path="*" element={<NotFound />} />
            </Routes>
          </Layout>
        </ErrorBoundary>
      </BrowserRouter>
    );
  }
}

export default Root;
