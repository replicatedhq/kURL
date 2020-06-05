import * as React from "react";
import * as debounce from "lodash/debounce";

const handlers = [];

function defferedHandlerCaller() {
  handlers.forEach((handle) => {
    if (typeof handle === "function") {
      handle();
    }
  });
}

export function Resizer(config = {}) {
  const { onResize } = config;
  const debounceTime = config.debounce || 500;

  return function decorateClass(DecoratedComponent) {
    return class Resize extends React.Component {

      constructor(...args) {
        super(...args);
        this.state = this.getState();
        this.onWindowResize = debounce(this.onWindowResize.bind(this), debounceTime);
      }

      getState() {
        if (typeof onResize === "function") {
          const determinedWindow = typeof window === "object" ? window : {};
          const newState = onResize(determinedWindow);
          if (newState && typeof newState === "object") {
            return newState;
          }
        }
        return {};
      }

      onWindowResize() {
        this.setState(this.getState());
      }

      componentDidMount() {
        this._registeredIndex = handlers.length;
        handlers.push(this.onWindowResize);

        window.addEventListener("resize", () => {
          setTimeout(defferedHandlerCaller, 0);
        });
      }

      componentWillUnmount() {
        // just place null in place to not throw off index
        handlers.splice(this._registeredIndex, 1, null);
      }

      render() {
        return (
          <DecoratedComponent {...this.props} {...this.state} ref="child" />
        );
      }
    };
  };
}
