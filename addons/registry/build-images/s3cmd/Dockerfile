FROM alpine:3.15

RUN apk add --no-cache \
    ca-certificates \
    py-dateutil \
    py-magic \
  && ln -s /usr/bin/python3 /usr/bin/python

# Install s3cmd
ENV S3CMD_VERSION=2.1.0
RUN wget https://github.com/s3tools/s3cmd/releases/download/v${S3CMD_VERSION}/s3cmd-${S3CMD_VERSION}.tar.gz \
  && tar -xzvf s3cmd-${S3CMD_VERSION}.tar.gz \
  && mv s3cmd-${S3CMD_VERSION}/s3cmd /usr/local/bin/s3cmd \
  && mv s3cmd-${S3CMD_VERSION}/S3 /usr/local/bin/S3 \
  && rm -rf s3cmd-${S3CMD_VERSION}*
