FROM ubuntu:24.04 AS build
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
WORKDIR /app
COPY --chown=flutter:flutter pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY --chown=flutter:flutter lib ./lib
COPY --chown=flutter:flutter web ./web
RUN flutter build web --release --no-wasm-dry-run \
    && VERSION=$(find build/web -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1) \
    && printf '{"version":"%s"}\n' "$VERSION" > build/web/deploy-version.json \
    && sed -i "s/__DEPLOY_VERSION__/$VERSION/g" build/web/updates.js build/web/flutter_bootstrap.js \
    && sed -i "s/flutter_bootstrap.js/flutter_bootstrap.js?v=$VERSION/; s/updates.js/updates.js?v=$VERSION/" build/web/index.html

FROM nginx:stable-alpine
ENV BACKEND_ORIGIN=http://api:3000
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
