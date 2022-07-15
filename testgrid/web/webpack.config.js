const webpack = require("webpack");
const { merge } = require("webpack-merge");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const MonacoWebpackPlugin = require("monaco-editor-webpack-plugin");
const ESLintPlugin = require("eslint-webpack-plugin");

module.exports = (env) => {
  let appEnv;
  if (env.production) {
    appEnv = require("./env/production.js");
  } else if (env.staging) {
    appEnv = require("./env/staging.js");
  } else if (env.okteto) {
    appEnv = require("./env/okteto.js");
  } else {
    appEnv = require("./env/development.js");
  }

  const common = {
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
              loader: "sass-loader"
            },
            {
              loader: "postcss-loader",
              options: {
                postcssOptions: {
                  plugins: [
                    ["autoprefixer"]
                  ]
                }
              }
            },
          ],
        },
        {
          test: /\.(png|jpg|ico|svg)$/,
          loader: "file-loader",
          exclude: /src\/assets\/scss\//,
        },
        {
          test: /\.woff(2)?(\?v=\d+\.\d+\.\d+)?$/,
          use: {
            loader: 'url-loader',
            options: {
              limit: 10000,
              mimetype: 'application/font-woff',
              name: './assets/[fullhash].[ext]'
            }
          }
        },
        {
          test: /\.(ttf|eot)$/,
          use: {
            loader: 'file-loader',
            options: {
              name: 'fonts/[fullhash].[ext]'
            }
          }
        },
        {
          test: /\.json$/,
          loader: 'json-loader'
        },
        {
          test: /\.ejs$/,
          loader: 'ejs-loader',
          options: {
            esModule: false
          }
        }
      ]
    },

    plugins: [
      new webpack.IgnorePlugin({
        resourceRegExp: /^\.\/locale$/,
        contextRegExp: /moment$/,
      }),
      new ESLintPlugin(),
      new HtmlWebpackPlugin({
        template: "./src/index.ejs",
        title: "kurl.sh test grid",
        favicon: "./src/assets/images/favicon-64.png",
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
        inject: "body",
        window: {
          env: appEnv,
        },
      }),
			new webpack.ContextReplacementPlugin(
				/graphql-language-service-interface[\\/]dist$/,
				new RegExp(`^\\./.*\\.js$`)
      ),
      new MonacoWebpackPlugin({
        languages: ["yaml", "json"],
        features: ["!anchorSelect"]
      }),
    ],
  };

  if (env.production) {
    const prod = require("./webpack.prod.config");
    return merge(common, prod);
  } else if (env.staging) {
    const staging = require("./webpack.staging.config");
    return merge(common, staging);
  } else if (env.okteto) {
    const staging = require("./webpack.okteto.config");
    return merge(common, staging);
  } else {
    const dev = require("./webpack.dev.config");
    return merge(common, dev);
  }
};
