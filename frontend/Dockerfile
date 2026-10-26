# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS flutter-sdk
ARG FLUTTER_VERSION=3.47.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils libglu1-mesa && rm -rf /var/lib/apt/lists/*
RUN groupadd --gid 10001 flutter \
    && useradd --uid 10001 --gid flutter --create-home --shell /bin/bash flutter \
    && install -d -o flutter -g flutter /opt/flutter /app
ENV HOME=/home/flutter \
    PUB_CACHE=/home/flutter/.pub-cache \
    PATH="/opt/flutter/bin:${PATH}"
USER flutter:flutter
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
RUN flutter precache --web

FROM flutter-sdk AS build
ARG TARGETARCH
WORKDIR /app
RUN mkdir -p .dart_tool
COPY --chown=flutter:flutter pubspec.yaml pubspec.lock ./
COPY --chown=flutter:flutter lib ./lib
COPY --chown=flutter:flutter web ./web
# Resolve once per build, including when BuildKit has discarded a cache mount.
# Seed Pub with the SDK's packages; keep only compiler intermediates in cache.
RUN --mount=type=cache,id=hevy-pub-${FLUTTER_VERSION}-${TARGETARCH},from=flutter-sdk,source=/home/flutter/.pub-cache,target=/home/flutter/.pub-cache,uid=10001,gid=10001,sharing=locked \
    --mount=type=cache,id=hevy-flutter-build-${FLUTTER_VERSION}-${TARGETARCH},target=/app/.dart_tool/flutter_build,uid=10001,gid=10001,sharing=locked \
    test "$(id -u)" -eq 10001 \
    && PUB_CACHE_LOCK="$PUB_CACHE/.hevy-lock-$(sha256sum pubspec.lock | cut -d ' ' -f 1)" \
    && if [ ! -f "$PUB_CACHE_LOCK" ] || ! flutter pub get --offline --enforce-lockfile; then \
         flutter pub get --enforce-lockfile; \
       fi \
    && touch "$PUB_CACHE_LOCK" \
    && flutter build web --release --no-pub --no-wasm-dry-run \
    && VERSION=$(find build/web -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1) \
    && printf '{"version":"%s"}\n' "$VERSION" > build/web/deploy-version.json \
    && sed -i "s/__DEPLOY_VERSION__/$VERSION/g" build/web/updates.js build/web/flutter_bootstrap.js \
    && sed -i "s/flutter_bootstrap.js/flutter_bootstrap.js?v=$VERSION/; s/updates.js/updates.js?v=$VERSION/" build/web/index.html

FROM nginx:stable-alpine
ENV BACKEND_ORIGIN=http://api:3000
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
