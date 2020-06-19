import * as React from "react";
import * as autobind from "react-autobind";
import { BrowserRouter, Route, Switch } from "react-router-dom";
import { ReflexProvider } from "reflexbox";
import ErrorBoundary from "./containers/ErrorBoundary";
import NotFound from "./shared/NotFound";
import Home from "./containers/Home";
import Run from "./containers/Run";
import Layout from "./shared/Layout";

import "../assets/scss/index.scss";

class Root extends React.Component {
  constructor(props) {
    autobind(this);
  }

  render() {
    return (
      <ReflexProvider>
        <BrowserRouter>
          <ErrorBoundary>
            <Layout title={"kURL Test Grid"}>
              <Switch>
                <Route exact path="/" component={Home} />
                <Route exact path="/run/:runId" component={Run} />
                <Route path="*" component={NotFound} />
              </Switch>
            </Layout>
          </ErrorBoundary>
        </BrowserRouter>
      </ReflexProvider>
    );
  }
};

export default Root;
