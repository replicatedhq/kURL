#!/bin/bash
sed -i 's/###_GRAPHQL_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/graphql/g' /usr/share/nginx/html/index.html
sed -i 's/###_REST_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/api/g' /usr/share/nginx/html/index.html
sed -i 's/###_GITHUB_CLIENT_ID_###/not-supported/g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPDOWNLOAD_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/api\/v1\/download/g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPINIT_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/api\/v1\/init\//g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPUPDATE_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/api\/v1\/update\//g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPEDIT_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/api\/v1\/edit\//g' /usr/share/nginx/html/index.html
sed -i 's/###_GITHUB_REDIRECT_URI_###/https:\/\/###_HOSTNAME_###\/auth\/github\/callback/g' /usr/share/nginx/html/index.html
sed -i 's/###_GITHUB_INSTALL_URL_###/not-supportetd/g' /usr/share/nginx/html/index.html
sed -i 's/###_INSTALL_ENDPOINT_###/https:\/\/###_HOSTNAME_###\/api\/install/g' /usr/share/nginx/html/index.html

sed -i "s/'self'/'self' ###_HOSTNAME_###/g" /etc/nginx/conf.d/default.conf

nginx -g "daemon off;"
