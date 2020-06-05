import * as React from "react";
import * as autobind from "react-autobind";
import { BrowserRouter, Route, Redirect, Switch } from "react-router-dom";
import { ReflexProvider } from "reflexbox";
import { Helmet } from "react-helmet";
import ErrorBoundary from "./containers/ErrorBoundary";
import NotFound from "./shared/NotFound";
import Home from "./containers/Home";
import Run from "./containers/Run";

import "../assets/css/index.css";

class Root extends React.Component {
  constructor(props) {
    autobind(this);
  }

  render() {
    return (
      <ReflexProvider>
        <BrowserRouter>
          <ErrorBoundary>
            <Switch>
              <Route exact path="/" component={Home} />
              <Route exact path="/run/:runId" component={Run} />
              <Route path="*" component={NotFound} />
            </Switch>
          </ErrorBoundary>
        </BrowserRouter>
      </ReflexProvider>
    );
  }
};

export default Root;
