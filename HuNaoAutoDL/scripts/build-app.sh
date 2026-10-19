#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$ROOT/.." && pwd)"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="胡闹AutoDL.app"
APP="$DIST_DIR/$APP_NAME"
# Sign outside the Documents file-provider scope; it keeps re-adding FinderInfo
# xattrs that make codesign fail with "resource fork ... not allowed".
STAGE="$(mktemp -d /tmp/hunao-build.XXXXXX)"
STAGE_APP="$STAGE/$APP_NAME"

mkdir -p "$BUILD_DIR" "$DIST_DIR"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"

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

cp "$BUILD_DIR/HuNaoAutoDL" "$STAGE_APP/Contents/MacOS/HuNaoAutoDL"
cp "$ROOT/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE_APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/BrandIcon.png" "$STAGE_APP/Contents/Resources/BrandIcon.png"
printf 'APPL????' > "$STAGE_APP/Contents/PkgInfo"

echo "→ 签名…"
signed=false
for attempt in 1 2 3; do
  xattr -cr "$STAGE_APP"
  if codesign --force --deep --sign - --identifier "com.hunao.autodl" "$STAGE_APP" >/dev/null 2>&1; then
    xattr -cr "$STAGE_APP"
    if codesign --verify --deep --strict "$STAGE_APP" 2>/dev/null; then
      signed=true
      break
    fi
  fi
  sleep 0.4
done
if [[ "$signed" != true ]]; then
  echo "codesign failed after 3 attempts" >&2
  exit 1
fi

rm -rf "$APP"
ditto --noextattr --norsrc "$STAGE_APP" "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"

echo "→ 完成：$APP"
