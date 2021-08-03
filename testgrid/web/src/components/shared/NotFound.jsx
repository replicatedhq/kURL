import * as React from "react";
import { Link } from "react-router-dom";

export default class NotFound extends React.Component {

  render() {
    const { breakpoint } = this.props;
    const isMobile = breakpoint === "mobile";
    return (
      <div className="u-minHeight--full u-width--full u-overflow--auto flex-column flex1 justifyContent--center alignItems--center u-position--relative">
        <div className="u-flexTabletReflow flex-auto u-width--full">
          <div className={`flex1 flex-column flex-verticalCenter justifyContent--center IllustrationContent-wrapper ${isMobile ? "alignItems--center" : "alignItems--flexEnd"}`}>
            <span className="icon u-notFound"></span>
          </div>
          <div className="Text-wrapper flex-column flex-verticalCenter flex1">
            <div className="Text">
              <p className="u-fontSize--giant u-fontWeight--light u-color--tuna u-lineHeight--same">
                Error 404
              </p>
              <p className="u-marginTop--more u-color--dustyGray u-fontSize--large u-lineHeight--normal">
                Oops, we couldn&apos;t find the page you were looking for
              </p>
              <div className="u-marginTop--more">
                <Link to="/" className="Button primary large">Take me home</Link>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }
}
