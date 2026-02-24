FROM alpine:3

RUN apk add --no-cache \
    ca-certificates \
    py-dateutil \
    py-magic

# Install s3cmd
RUN S3CMD_VERSION=$(wget -qO- https://api.github.com/repos/s3tools/s3cmd/releases/latest | \
    grep '"name":' | \
    grep -Eo "[0-9]+\.[0-9]+\.[0-9]+" | \
    head -1) \
  && wget https://github.com/s3tools/s3cmd/releases/download/v${S3CMD_VERSION}/s3cmd-${S3CMD_VERSION}.tar.gz \
  && tar -xzvf s3cmd-${S3CMD_VERSION}.tar.gz \
  && mv s3cmd-${S3CMD_VERSION}/s3cmd /usr/local/bin/s3cmd \
  && mv s3cmd-${S3CMD_VERSION}/S3 /usr/local/bin/S3 \
  && rm -rf s3cmd-${S3CMD_VERSION}*
