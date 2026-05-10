# --- builder ---
# Match the SDK floor in pubspec.yaml (>=3.3.0) and the API surface used by
# the codebase (Color.withValues / Color.r/.g/.b — Flutter 3.27+).
FROM ghcr.io/cirruslabs/flutter:3.27.0 AS builder
WORKDIR /src
COPY pubspec.yaml ./
RUN flutter pub get
COPY . .
ARG API_BASE=https://cup-admin.douwen.me
ARG WS_BASE=wss://cup-admin.douwen.me/ws
RUN flutter build web --release --no-tree-shake-icons \
      --dart-define=API_BASE=${API_BASE} \
      --dart-define=WS_BASE=${WS_BASE}

# Bust upstream caches (Cloudflare / host nginx / Telegram WebView) by
# rewriting the entry-point references with a build-time version stamp.
# nginx.conf already sends no-cache headers for the entry files, but
# intermediaries that ignore those headers will still see a different
# URL each build and re-fetch.
RUN BUILD_VER=v$(date +%s) \
 && cd /src/build/web \
 && cp main.dart.js main.dart.${BUILD_VER}.js \
 && sed -i "s|\"mainJsPath\":\"main\\.dart\\.js\"|\"mainJsPath\":\"main.dart.${BUILD_VER}.js\"|" flutter_bootstrap.js \
 && cp flutter_bootstrap.js flutter_bootstrap.${BUILD_VER}.js \
 && sed -i "s|flutter_bootstrap\\.js|flutter_bootstrap.${BUILD_VER}.js|g" index.html \
 && echo "${BUILD_VER}" > build_version.txt

# --- runtime ---
FROM nginx:1.27-alpine
COPY --from=builder /src/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
