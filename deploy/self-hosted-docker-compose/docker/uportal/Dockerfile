FROM golang:1.24-alpine AS shhoook-builder

ARG SHHOOOK_ARCHIVE_URL=https://github.com/mopkob1/shhoook/archive/refs/heads/main.tar.gz

ADD ${SHHOOOK_ARCHIVE_URL} /tmp/shhoook.tar.gz
RUN set -eu; \
    mkdir -p /out /src; \
    tar -xzf /tmp/shhoook.tar.gz -C /src --strip-components=1; \
    if find /src/src -maxdepth 1 -type f -name '*.go' | grep -q .; then cd /src/src; else cd /src; fi; \
    CGO_ENABLED=0 GOOS=linux GO111MODULE=off go build -o /out/shhoook .; \
    test -x /out/shhoook

FROM node:22-alpine AS admin-builder

WORKDIR /src/admin
ARG UPORTAL_BASE_URL
ARG UPORTAL_UI_LANG=en
ENV VITE_UPORTAL_DEFAULT_SERVER_URL=${UPORTAL_BASE_URL}

COPY admin/package*.json ./
RUN npm ci
COPY admin ./
RUN set -eu; \
    npm run build -- --base=/ui/; \
    lang="$(printf '%s' "${UPORTAL_UI_LANG:-en}" | tr '[:upper:]' '[:lower:]' | cut -d- -f1)"; \
    case "$lang" in ru|en|es) ;; *) lang="en" ;; esac; \
    node -e "const fs=require('fs'); const p='dist/index.html'; const lang=process.argv[1]; fs.writeFileSync(p, fs.readFileSync(p, 'utf8').replace(\"localStorage.getItem('uportal_lang') || 'en'\", \"localStorage.getItem('uportal_lang') || '\" + lang + \"'\"));" "$lang"

FROM alpine:3.20 AS plugin-builder

RUN apk add --no-cache jq zip sed
WORKDIR /src/plugin/source
ARG UPORTAL_PLUGIN_DEFAULT_BASE_URL
ARG UPORTAL_BASE_URL
ARG UPORTAL_DOMAIN
ARG UPORTAL_UI_LANG=en
COPY VERSION /src/VERSION
COPY plugin/source ./
RUN set -eu; \
    base="${UPORTAL_PLUGIN_DEFAULT_BASE_URL:-${UPORTAL_BASE_URL:-}}"; \
    if [ -z "$base" ]; then base="https://${UPORTAL_DOMAIN}"; fi; \
    base="${base%/}"; \
    case "$base" in *'$'*|*'{'*|*'}'*) base="https://${UPORTAL_DOMAIN}" ;; esac; \
    lang="$(printf '%s' "${UPORTAL_UI_LANG:-en}" | tr '[:upper:]' '[:lower:]' | cut -d- -f1)"; \
    case "$lang" in ru|en|es) ;; *) lang="en" ;; esac; \
    test -n "$base"; \
    find . -type f -exec sed -i \
      -e "s|http://localhost:8080/api/admin/dictionary|$base/api/admin/dictionary|g" \
      -e "s|http://localhost:8080/link-fallback|$base/link-fallback|g" \
      -e "s|http://localhost:8080|$base|g" \
      {} +; \
    jq --arg lang "$lang" '.preferred = $lang | .default = $lang' captions.json > captions.json.tmp; \
    mv captions.json.tmp captions.json; \
    sh scripts/pack.sh

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      bash \
      nginx \
      libnginx-mod-http-js \
      pandoc \
      procps; \
    rm -rf /var/lib/apt/lists/*

COPY runtime /opt/uportal/runtime
COPY VERSION /opt/uportal/VERSION
COPY deploy/self-hosted-docker-compose/docker/uportal/nginx.conf /etc/nginx/nginx.conf
COPY deploy/self-hosted-docker-compose/docker/uportal/entrypoint.sh /usr/local/bin/uportal-container-entrypoint
COPY --from=shhoook-builder /out/shhoook /usr/local/bin/shhoook
COPY --from=admin-builder /src/admin/dist /opt/uportal/build/admin
COPY --from=plugin-builder /src/plugin/uportal-link-inserter.xpi /opt/uportal/build/plugin/uportal-link-inserter.xpi

RUN set -eu; \
    chmod 755 /usr/local/bin/uportal-container-entrypoint /usr/local/bin/shhoook; \
    find /opt/uportal/runtime/scripts -maxdepth 1 -type f -name '*.sh' -exec chmod 755 {} \;

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/uportal-container-entrypoint"]
