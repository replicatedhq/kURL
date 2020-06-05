import * as React from "react";
import { Flex, Box } from "reflexbox";
import { Fill } from "../shared/Fill";

export default class Footer extends React.Component {

  render() {
    return (
      <footer>
        <Flex justify="center" w={1} p={2}>
          <Fill w={"100%"}>
            <Flex>
              <Box w={2 / 5}>
                Copyright 2020, Replicated, Inc.
              </Box>
              <Box w={1 / 5} p={10}>
              </Box>
              <Box w={1 / 5} p={10}>
              </Box>
              <Box w={1 / 5} p={10}>
              </Box>
            </Flex>
          </Fill>
        </Flex>
      </footer>
    );
  }
}
