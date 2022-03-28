var path = require("path");
const BundleAnalyzerPlugin = require("webpack-bundle-analyzer").BundleAnalyzerPlugin;

var srcPath = path.join(__dirname, "src");
var distPath = path.join(__dirname, "dist");

module.exports = {
  mode: 'development',

  entry: [
    "./src/index.jsx",
  ],

  module: {
    rules: [
      {
        test: /\.jsx?$/,
        use: 'ts-loader',
        include: srcPath,
        enforce: "pre",
      },
      {
        test: /\.jsx?$/,
        use: "source-map-loader",
        include: srcPath,
        enforce: "pre",
      },
    ],
  },

  optimization: {
    moduleIds: "named",
  },

  output: {
    path: distPath,
    publicPath: "/",
    filename: "testgrid.js",
  },

  devtool: "eval-source-map"
};
