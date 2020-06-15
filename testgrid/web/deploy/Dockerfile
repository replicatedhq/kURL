FROM node:10.19.0
ADD . /src
WORKDIR /src
EXPOSE 3000
RUN make deps

RUN make build-staging build-prod build-kots

FROM nginx:latest
COPY --from=0 /src/dist-staging /usr/share/nginx/staging
COPY --from=0 /src/dist-prod /usr/share/nginx/production
COPY --from=0 /src/dist-kots /usr/share/nginx/kots

COPY deploy/default.conf /etc/nginx/conf.d/default.template

STOPSIGNAL SIGTERM

