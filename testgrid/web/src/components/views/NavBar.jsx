import * as React from "react";
import { Link } from "react-router-dom";

import "../../assets/scss/components/NavBar.scss";

export default class extends React.Component {
  render() {
    return (
      <div className="NavBarWrapper">
        {window.location.pathname !== "/" && <Link to="/" className="home-btn"><span>{`< Home`}</span></Link>}
        <div className="Logo" />
      </div>
    );
  }
}
