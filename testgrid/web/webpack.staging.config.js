var path = require("path");
var webpack = require("webpack");
const BundleAnalyzerPlugin = require("webpack-bundle-analyzer").BundleAnalyzerPlugin;

var srcPath = path.join(__dirname, "src");
var distPath = path.join(__dirname, "dist-staging");

module.exports = {
  mode: 'production',

  entry: [
    "./src/index.jsx",
  ],

  module: {
    rules: [
      {
        test: /\.jsx?$/,
        include: srcPath,
        enforce: "pre",
        use: 'ts-loader',
      },
    ],
  },

  plugins: [
    new BundleAnalyzerPlugin({
      analyzerMode: "disabled",
      generateStatsFile: true,
      statsOptions: { source: false }
    }),
  ],

  optimization: {
    moduleIds: "named",
  },

  output: {
    path: distPath,
    publicPath: "/",
    filename: "kurltestgrid.[fullhash].js",
  },

  devtool: false,

  stats: {
    colors: true,
    reasons: false
  },
};
