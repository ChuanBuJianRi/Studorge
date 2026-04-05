#!/usr/bin/env bash
# build_app.sh — Packages Studorge into a native macOS .app bundle.
#
# Usage:
#   chmod +x build_app.sh
#   ./build_app.sh
#
# Output:
#   dist/Studorge.app     — drag to /Applications to install
#   dist/Studorge.dmg     — (optional) distributable disk image

set -euo pipefail

APP_NAME="Studorge"
BUNDLE_ID="com.studorge.app"
VERSION="1.0.0"
PORT=8000

SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIST="$SRC_DIR/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_SRC="$RESOURCES/app"    # bundled source copy

echo "╔══════════════════════════════════════════╗"
echo "║   Building $APP_NAME.app v$VERSION          ║"
echo "╚══════════════════════════════════════════╝"

# ── Clean ──────────────────────────────────────────────────────────────────
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# ── Icon: PNG → ICNS ──────────────────────────────────────────────────────
ICON_PNG="$SRC_DIR/frontend/app-icon.png"
ICON_ICNS="$RESOURCES/AppIcon.icns"

if [ -f "$ICON_PNG" ]; then
    echo "→ Creating AppIcon.icns…"
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png"      &>/dev/null
        sips -z $((size*2)) $((size*2)) "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" &>/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
    rm -rf "$(dirname "$ICONSET")"
    echo "   ✓ AppIcon.icns"
fi

# ── Copy source code into bundle ──────────────────────────────────────────
echo "→ Bundling source code…"
mkdir -p "$APP_SRC"

rsync -a --delete \
    --exclude="__pycache__" \
    --exclude="*.pyc" \
    --exclude=".git" \
    --exclude="dist" \
    --exclude="build" \
    --exclude="*.egg-info" \
    --exclude="chroma_db" \
    --exclude="studorge.db" \
    --exclude=".env" \
    --exclude="scripts" \
    "$SRC_DIR/backend/"      "$APP_SRC/backend/"
rsync -a --delete \
    --exclude="*.pyc" \
    "$SRC_DIR/frontend/"     "$APP_SRC/frontend/"
cp "$SRC_DIR/requirements.txt"  "$APP_SRC/"
cp "$SRC_DIR/run.py"            "$APP_SRC/"
[ -f "$SRC_DIR/.env.example" ] && cp "$SRC_DIR/.env.example" "$APP_SRC/"

echo "   ✓ Source bundled"

# ── Launcher script (inside Resources) ────────────────────────────────────
echo "→ Writing launcher script…"
cp "$SRC_DIR/scripts/studorge_launcher.sh" "$RESOURCES/studorge_launcher.sh"
chmod +x "$RESOURCES/studorge_launcher.sh"

# ── MacOS stub: the .app entry-point ──────────────────────────────────────
cat > "$MACOS/$APP_NAME" <<'STUB'
#!/usr/bin/env bash
# Entry-point executed by macOS when the user double-clicks the .app.
RESOURCES="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../Resources" && pwd )"
exec "$RESOURCES/studorge_launcher.sh"
STUB
chmod +x "$MACOS/$APP_NAME"

# ── Info.plist ────────────────────────────────────────────────────────────
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>    <string>12.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSUIElement</key>               <false/>
</dict>
</plist>
PLIST

echo "   ✓ Info.plist"

# ── PkgInfo ───────────────────────────────────────────────────────────────
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# ── Verify ───────────────────────────────────────────────────────────────
echo ""
echo "✅  Build complete!"
echo "   App:  $APP"
echo ""

# ── Optional: Create DMG ─────────────────────────────────────────────────
read -r -p "Create distributable DMG? [y/N] " MAKE_DMG
if [[ "${MAKE_DMG:-n}" =~ ^[Yy]$ ]]; then
    DMG="$DIST/$APP_NAME-$VERSION.dmg"
    echo "→ Creating $APP_NAME-$VERSION.dmg…"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP" \
        -ov -format UDZO \
        "$DMG" &>/dev/null
    echo "✅  DMG: $DMG"
fi

echo ""
echo "📦  To install: drag $APP_NAME.app to your /Applications folder."
echo "🚀  Or run directly: open \"$APP\""
echo ""

# Ask to launch now
read -r -p "Launch $APP_NAME now? [Y/n] " LAUNCH
if [[ ! "${LAUNCH:-y}" =~ ^[Nn]$ ]]; then
    open "$APP"
fi
