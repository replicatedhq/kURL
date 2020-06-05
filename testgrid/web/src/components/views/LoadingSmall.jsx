import * as React from "react";
import { Flex } from "reflexbox";
import { Fill } from "../shared/Fill";
import { BeatLoader } from "react-spinners";

export default class LoadingSmall extends React.Component {

  render() {
    if (!this.props.isLoading) {
      return <span />;
    }

    return (
      <Flex align="center" justify="center" column w={1}>
        <Fill>
          <BeatLoader
            color={"#9B9B9B"}
            loading={this.props.isLoading} />
        </Fill>
      </Flex>
    );
  }
}
