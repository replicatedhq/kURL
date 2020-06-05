import * as React from "react";
import * as ReactDOM from "react-dom";
import Root from "./Root";

// get the config from the server
fetch(`${window.env.API_ENDPOINT}/config`, { })
  .then(res => res.json())
  .then((config) => {
    ReactDOM.render((<Root />), document.getElementById("app"));
  })
  .catch((err) => {
    console.error(err);
  });

