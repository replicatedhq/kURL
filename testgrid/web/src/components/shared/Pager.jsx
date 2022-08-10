import * as React from "react";
import * as PropTypes from "prop-types";
import { formatNumber } from "accounting";

import "../../assets/scss/shared/Pager.scss";

class Pager extends React.Component {
  pageCount() {
    return Math.ceil(this.props.totalCount / this.props.pageSize);
  }

  offset() {
    return this.props.currentPage * this.props.pageSize;
  }

  handleGoToPage(page, e) {
    this.props.goToPage(page, e);
  }

  render() {
    return (
      <div className="flex flex-auto Pager justifyContent--center u-width--half">
        {this.props.currentPage > 0 ?
          <div className="flex-column justifyContent--center u-marginRight--50">
            <div className="flex arrow-wrapper">
              <p
                className="u-fontSize--normal u-color--dustyGray u-fontWeight--medium u-lineHeight--normal u-cursor--pointer u-display--inlineBlock"
                onClick={!this.props.loading ? (e) => this.handleGoToPage(this.props.currentPage - 1, e) : null}
              >
                <span className="previous">{"< Previous"}</span>
              </p>
            </div>
          </div>
        : null}
        <div className="flex-auto resultsCount">
          {this.props.currentPageLength
            ? <p className="u-fontSize--normal u-lineHeight--normal u-textAlign--center">
              <span className="u-color--dustyGray">Showing {this.props.pagerType} </span>
              <span className="u-color--tuna u-fontWeight--medium">{`${this.offset() + 1} - ${this.offset() + this.props.currentPageLength}`}</span>
              <span className="u-color--dustyGray"> of </span>
              <span className="u-color--tuna u-fontWeight--medium">{formatNumber(this.props.totalCount)}</span>
            </p>
            : null}
        </div>
        <div className="flex-column justifyContent--center u-marginLeft--50">
          {this.props.currentPage < (this.pageCount() - 1) ?
            <div className="flex arrow-wrapper">
              <p
                className="u-fontSize--normal u-color--dustyGray u-fontWeight--medium u-lineHeight--normal u-cursor--pointer u-display--inlineBlock"
                onClick={!this.props.loading ? (e) => this.handleGoToPage(this.props.currentPage + 1, e) : null}
              >
                <span className="previous">{"Next >"}</span>
              </p>
            </div>
            : null}
        </div>
      </div>
    )
  }
}

Pager.propTypes = {
  pagerType: PropTypes.string,
  currentPage: PropTypes.number.isRequired,
  pageSize: PropTypes.number.isRequired,
  totalCount: PropTypes.number.isRequired,
  loading: PropTypes.bool.isRequired,
  currentPageLength: PropTypes.number.isRequired
}

export default Pager;
