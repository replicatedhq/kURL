module.exports = {
  ENVIRONMENT: "development",
  API_ENDPOINT: `https://tgapi-${ process.env.OKTETO_NAMESPACE }.okteto.repldev.com/api/v1`,
  WEBPACK_SCRIPTS: [
    "https://unpkg.com/react@17/umd/react.production.min.js",
    "https://unpkg.com/react-dom@17/umd/react-dom.production.min.js",
  ]
};
