#!/bin/bash
sed -i 's/###_GRAPHQL_ENDPOINT_###/http:\/\/${HOSTNAME}\/graphql/g' /usr/share/nginx/html/index.html
sed -i 's/###_REST_ENDPOINT_###/http:\/\/${HOSTNAME}\/api/g' /usr/share/nginx/html/index.html
sed -i 's/###_GITHUB_CLIENT_ID_###/not-supported/g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPDOWNLOAD_ENDPOINT_###/http:\/\/${HOSTNAME}\/api\/v1\/download/g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPINIT_ENDPOINT_###/http:\/\/${HOSTNAME}\/api\/v1\/init\//g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPUPDATE_ENDPOINT_###/http:\/\/${HOSTNAME}\/api\/v1\/update\//g' /usr/share/nginx/html/index.html
sed -i 's/###_SHIPEDIT_ENDPOINT_###/http:\/\/${HOSTNAME}\/api\/v1\/edit\//g' /usr/share/nginx/html/index.html
sed -i 's/###_GITHUB_REDIRECT_URI_###/http:\/\/${HOSTNAME}\/auth\/github\/callback/g' /usr/share/nginx/html/index.html
sed -i 's/###_GITHUB_INSTALL_URL_###/not-supportetd/g' /usr/share/nginx/html/index.html
sed -i 's/###_INSTALL_ENDPOINT_###/http:\/\/${HOSTNAME}\/api\/install/g' /usr/share/nginx/html/index.html

nginx -g "daemon off;"
