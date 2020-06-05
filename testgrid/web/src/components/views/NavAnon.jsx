import * as React from "react";
import { Link } from "react-router-dom";
import { Flex, Box } from "reflexbox";
import { Fill } from "../shared/Fill";


export default class extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      isHamburgerOpen: false,
    };
  }

  onToggleHamburger = (ev) => {
    ev.preventDefault();

    this.setState({
      isHamburgerOpen: !this.state.isHamburgerOpen,
    });
  }

  render() {
    return (
      <Flex mx="auto" column w={1200}>
        <header className="bg-dark text-white sm small-display-none">
          <Flex w={1} p={2}>
              <Box>
              <Link to="/"><Logo className="logo" /></Link>
              </Box>
              <Box ml="auto" p={8} my={9} color="#fff">
                <Flex className="nav-links">
                  <Box px={2}>

                  </Box>
                  <Box px={2}>

                  </Box>
                  <Box px={2}>

                  </Box>
                </Flex>
              </Box>
            </Flex>
        </header>
      </Flex>
    );
  }
}
