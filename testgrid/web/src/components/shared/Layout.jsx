import * as React from "react";
import * as PropTypes from "prop-types";
import NavBar from "./NavBar";
import Footer from "./Footer";
import { Helmet } from "react-helmet";

import ReplLogoWhite from "../../assets/images/repl-white.svg";

import "../../assets/scss/shared/Layout.scss";

const Layout = ({ children, title }) => {
  return (
    <div className="flex flex1">
      <div className="suite-banner">
        <div className="flex flex-row justifyContent--spaceBetween">
          <img src={ReplLogoWhite} />
          <div>
            <a href="https://blog.replicated.com/kurl-with-replicated-kots/" target="_blank" rel="noopener noreferrer">Learn more about how kURL works with Replicated KOTS<span className="banner-arrow"></span></a>
          </div>
        </div>
      </div>
      <Helmet>
        <meta charSet="utf-8" />
        <title>{title}</title>
      </Helmet>
      <NavBar title={title} />
      <div className="u-minHeight--full u-width--full u-overflow--auto flex-column flex1">
        <main className="flex-column flex1 main-container">{children}</main>
        <div className="flex-auto Footer-wrapper u-width--full">
          <Footer />
        </div>
      </div>
    </div>
  )
}

Layout.propTypes = {
  children: PropTypes.node.isRequired,
}

export default Layout;