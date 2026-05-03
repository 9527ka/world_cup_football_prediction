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

# --- runtime ---
FROM nginx:1.27-alpine
COPY --from=builder /src/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
