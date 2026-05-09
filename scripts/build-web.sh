#!/usr/bin/env bash
# Build Flutter web with cache-busting version on all entry assets.
# Cloudflare/browsers cache by URL — appending ?v=<timestamp> forces a fresh
# fetch after each build without manual cache purge.
#
# Files versioned:
#   - index.html            references → flutter_bootstrap.js?v=TS, live_overlay.js?v=TS
#   - flutter_bootstrap.js  internal   → main.dart.js?v=TS
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER="${FLUTTER_BIN:-/Users/lang/flutter/bin/flutter}"

cd "$ROOT"
"$FLUTTER" build web --release "$@"

VER="$(date +%s)"
WEB="$ROOT/build/web"
SED='/usr/bin/sed -i ""'

# 1) index.html: bootstrap + live_overlay
/usr/bin/sed -i '' -E \
  -e "s#(flutter_bootstrap\.js)(\?v=[0-9]+)?#\1?v=$VER#g" \
  -e "s#(live_overlay\.js)(\?v=[0-9]+)?#\1?v=$VER#g" \
  "$WEB/index.html"

# 2) flutter_bootstrap.js: main.dart.js (only the bare ref, leave full URLs alone)
/usr/bin/sed -i '' -E \
  -e "s#\"main\.dart\.js(\?v=[0-9]+)?\"#\"main.dart.js?v=$VER\"#g" \
  "$WEB/flutter_bootstrap.js"

echo "✓ versioned with v=$VER"
echo "  index.html:"
grep -E "flutter_bootstrap\.js|live_overlay\.js" "$WEB/index.html" | sed 's/^/    /'
echo "  flutter_bootstrap.js:"
grep -oE "main\.dart\.js\?v=[0-9]+" "$WEB/flutter_bootstrap.js" | head -2 | sed 's/^/    /'
