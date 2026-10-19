#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT/.." && pwd)"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="胡闹AutoDL.app"
APP="$DIST_DIR/$APP_NAME"

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SWIFT_FILES=("${(@f)$(find "$ROOT/Sources" -name '*.swift' | sort)}")

echo "→ 编译 Swift 源码…"
swiftc \
  -O \
  -parse-as-library \
  -target arm64-apple-macosx15.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework WebKit \
  -framework UserNotifications \
  -framework Combine \
  -o "$BUILD_DIR/HuNaoAutoDL" \
  "${SWIFT_FILES[@]}"

cp "$BUILD_DIR/HuNaoAutoDL" "$APP/Contents/MacOS/HuNaoAutoDL"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ 签名…"
signed=false
for attempt in 1 2 3; do
  xattr -cr "$APP"
  if codesign --force --deep --sign - --identifier "com.hunao.autodl" "$APP" >/dev/null 2>&1; then
    signed=true
    break
  fi
  sleep 0.4
done
if [[ "$signed" != true ]]; then
  echo "codesign failed after 3 attempts" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"

echo "→ 完成：$APP"
