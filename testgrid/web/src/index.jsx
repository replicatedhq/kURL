import * as React from "react";
import { createRoot } from 'react-dom/client';
import Root from "./Root";

// get the config from the server
fetch(`${window.env.API_ENDPOINT}/config`, { })
  .then(res => res.json())
  .then(() => {
    const container = document.getElementById("app");
    const root = createRoot(container);
    root.render(<Root />);
  })
  .catch((err) => {
    console.error(err);
  });

