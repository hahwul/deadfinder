FROM crystallang/crystal:latest-alpine AS builder

RUN apk add --no-cache cmake make g++ git

WORKDIR /build
COPY crystal/ ./crystal/

WORKDIR /build/crystal
RUN shards install
RUN crystal build src/cli_main.cr -o /build/deadfinder --release --static --no-debug

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /build/deadfinder /usr/local/bin/deadfinder
CMD ["deadfinder"]
