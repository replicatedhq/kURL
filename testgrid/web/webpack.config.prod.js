var path = require("path");
var webpack = require("webpack");
var CopyWebpackPlugin = require("copy-webpack-plugin");
const BundleAnalyzerPlugin = require("webpack-bundle-analyzer").BundleAnalyzerPlugin;

var srcPath = path.join(__dirname, "src");
var distPath = path.join(__dirname, "dist-prod");

module.exports = {
  entry: [
    "./src/index.jsx",
  ],

  module: {
    rules: [
      {
        test: /\.jsx?$/,
        include: srcPath,
        enforce: "pre",
        loader: "tslint-loader",
      },
      {
        test: /\.jsx?$/,
        include: srcPath,
        loader: "awesome-typescript-loader",
      },
    ],
  },

  plugins: [
    new webpack.NamedModulesPlugin(),
    new webpack.DefinePlugin({
      "process.env": {
        NODE_ENV: JSON.stringify("production"),
      },
    }),
    new BundleAnalyzerPlugin({
      analyzerMode: "disabled",
      generateStatsFile: true,
      statsOptions: { source: false }
    }),
  ],

  output: {
    path: distPath,
    publicPath: "/",
    filename: "kurltestgrid.[hash].js",
  },

  devtool: false,

  stats: {
    colors: true,
    reasons: false
  },
};
