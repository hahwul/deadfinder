FROM crystallang/crystal:1.20.0-alpine AS builder

RUN apk add --no-cache cmake make g++ git

WORKDIR /build
COPY shard.yml shard.lock ./
COPY src/ ./src/

RUN shards install
RUN crystal build src/cli_main.cr -o /build/deadfinder --release --static --no-debug

FROM alpine:3.21

LABEL org.opencontainers.image.title="DeadFinder"
LABEL org.opencontainers.image.description="Find dead links (broken links)."
LABEL org.opencontainers.image.authors="HAHWUL <hahwul@gmail.com>"
LABEL org.opencontainers.image.source="https://github.com/hahwul/deadfinder"
LABEL org.opencontainers.image.documentation="https://github.com/hahwul/deadfinder"
LABEL org.opencontainers.image.licenses="MIT"

LABEL "com.github.actions.name"="DeadFinder"
LABEL "com.github.actions.description"="Find dead (broken) links in files, URLs, or sitemaps"
LABEL "com.github.actions.icon"="link"
LABEL "com.github.actions.color"="red"

ENV LC_ALL=C.UTF-8

RUN apk add --no-cache ca-certificates
COPY --from=builder /build/deadfinder /usr/local/bin/deadfinder
CMD ["deadfinder"]
