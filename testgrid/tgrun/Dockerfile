############################
FROM golang:1.15-alpine AS builder

RUN apk update && apk add --no-cache git ca-certificates && update-ca-certificates

COPY ./testgrid/tgrun /tgrun
COPY ./testgrid/tgapi /tgapi
COPY ./kurlkinds /kurlkinds

WORKDIR /tgrun

RUN go mod download
RUN go mod verify

RUN CGO_ENABLED=0 go build -o /go/bin/tgrun ./cmd/run

############################
FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /go/bin/tgrun /bin/tgrun

ENTRYPOINT ["/bin/tgrun"]
