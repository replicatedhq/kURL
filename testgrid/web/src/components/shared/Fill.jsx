import * as React from "react";
import { Box } from "reflexbox";
import { dark } from "./colors";

export class Fill extends React.Component {

  render() {
    return (
      <Box
        {...this.props}
        style={{
          ...this.props.style,
          color: this.props.color,
          backgroundColor: this.props.color,
          transitionProperty: "color",
          transitionDuration: "1s",
          transitionTimingFunction: "ease-out",
        }}/>
    );
  }
}
