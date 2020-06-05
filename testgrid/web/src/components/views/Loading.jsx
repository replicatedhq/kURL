import * as React from "react";
import { Flex } from "reflexbox";
import { Fill } from "../shared/Fill";
import { PropagateLoader } from "react-spinners";

export default class Loading extends React.Component {

  render() {
    if (!this.props.isLoading) {
      return <span />;
    }

    return (
      <Flex align="center" justify="center" column w={1} px={3} py={4}>
        <Fill p={2}>
          <PropagateLoader
            color={"#9B9B9B"}
            loading={this.props.isLoading} />
        </Fill>
      </Flex>
    );
  }
}
