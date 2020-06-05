const webpackMerge = require("webpack-merge");
const webpack = require("webpack");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const FaviconsWebpackPlugin = require("favicons-webpack-plugin");
const HtmlWebpackTemplate = require("html-webpack-template");
const path = require("path");
const MonacoWebpackPlugin = require("monaco-editor-webpack-plugin");

module.exports = function(env) {
  const appEnv = require("./env/" + (env || "development") + ".js");

  const common = {
    mode: env,

    resolve: {
      extensions: [".js", ".jsx", ".scss", ".css", ".png", ".jpg", ".svg", ".ico"],
    },

    module: {
      rules: [
        {
          test: /\.(css|scss)$/,
          use: [
            {
              loader: "style-loader"
            },
            {
              loader: "css-loader",
              options: {
                importLoaders: 2,
              }
            },
            {
              loader: "sass-loader",
              options: {
                includePaths: [
                  path.resolve(__dirname, "node_modules"),
                ],
              },
            },
            {
              loader: "postcss-loader"
            },
          ],
        },
        {
          test: /\.(png|jpg|ico)$/,
          loader: "file-loader",
        },
        {
          test: /\.svg$/,
          use: [
            {
              loader: "babel-loader"
            },
            {
              loader: "react-svg-loader",
              options: {
                jsx: true,
              },
            },
          ],
        },
        {
          test: /\.woff(2)?(\?v=\d+\.\d+\.\d+)?$/,
          loader: "url-loader?limit=10000&mimetype=application/font-woff&name=./assets/[hash].[ext]",
        },
        {
          test: /\.(ttf|eot)$/,
          use: {
            loader: 'file-loader',
            options: {
              name: 'fonts/[hash].[ext]'
            }
          }
        },
      ]
    },

    plugins: [
      new webpack.IgnorePlugin(/^\.\/locale$/, /moment$/),
      new HtmlWebpackPlugin({
        template: HtmlWebpackTemplate,
        title: "kurl.sh test grid",
        appMountId: "app",
        externals: [
          {
            "react-dom": {
              root: "ReactDOM",
              commonjs2: "react-dom",
              commonjs: "react-dom",
              amd: "react-dom"
            }
          },
          {
            "react": {
              root: "React",
              commonjs2: "react",
              commonjs: "react",
              amd: "react"
            }
          }
        ],
        scripts: appEnv.WEBPACK_SCRIPTS,
        inject: false,
        window: {
          env: appEnv,
        },
      }),
      new webpack.LoaderOptionsPlugin({
        options: {
          tslint: {
            emitErrors: true,
            failOnHint: true,
          },
        },
        postcss: [
          require("autoprefixer"),
        ],
      }),
			new webpack.ContextReplacementPlugin(
				/graphql-language-service-interface[\\/]dist$/,
				new RegExp(`^\\./.*\\.js$`)
      ),
      new MonacoWebpackPlugin({
        languages: ["yaml"]
      }),
    ],
  };

  if (env === "production") {
    const prod = require("./webpack.config.prod");
    return webpackMerge(common, prod);
  } else if (env === "staging") {
    const staging = require("./webpack.config.staging");
    return webpackMerge(common, staging);
  } else if (env === "kots" ) {
    const kots = require("./webpack.config.kots");
    return webpackMerge(common, kots);
  } else {
    const dev = require("./webpack.config.dev");
    return webpackMerge(common, dev);
  }
};
