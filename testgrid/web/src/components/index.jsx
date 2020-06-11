import * as React from "react";
import * as autobind from "react-autobind";
import { BrowserRouter, Route, Switch } from "react-router-dom";
import { ReflexProvider } from "reflexbox";
import ErrorBoundary from "./containers/ErrorBoundary";
import NotFound from "./shared/NotFound";
import Home from "./containers/Home";
import Run from "./containers/Run";
import NavBar from "./views/NavBar";

import "../assets/scss/index.scss";
import Footer from "./views/Footer";

class Root extends React.Component {
  constructor(props) {
    autobind(this);
  }

  render() {
    return (
      <ReflexProvider>
        <BrowserRouter>
          <ErrorBoundary>
            <NavBar />
            <Switch>
              <Route exact path="/" component={Home} />
              <Route exact path="/run/:runId" component={Run} />
              <Route path="*" component={NotFound} />
            </Switch>
            <Footer />
          </ErrorBoundary>
        </BrowserRouter>
      </ReflexProvider>
    );
  }
};

export default Root;
