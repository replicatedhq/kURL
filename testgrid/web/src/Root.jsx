import * as React from "react";
import ComponentRoot from "./components";
import { Helmet } from "react-helmet";

class Root extends React.Component {
  render() {
    return (
      <div className="flex-column flex1">
        <Helmet>
          <meta httpEquiv="Cache-Control" content="no-cache, no-store, must-revalidate" />
          <meta httpEquiv="Pragma" content="no-cache" />
          <meta httpEquiv="Expires" content="0" />
        </Helmet>
        <ComponentRoot />
      </div>
    );
  }
}

export default Root;
