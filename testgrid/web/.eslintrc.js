module.exports = {
  root: true,
  parser: "@typescript-eslint/parser",
  parserOptions: {
    requireConfigFile: false,
  },
  extends: [
    "eslint:recommended",
    "plugin:react/recommended",
  ],
  env: {
    browser: true,
    node: true,
    amd: true,
  },
  rules: {
    "react/prop-types": "off",
  },
  settings: {
    react: {
      version: "detect",
    }
  }
}
