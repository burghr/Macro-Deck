#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MacroDeck"
LABEL="com.macrodeck.app"
INSTALL_DIR="$HOME/Applications"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.mac-macro/macrodeck.log"

echo "==> Building $APP_NAME with xcodebuild (this takes ~30s)..."
cd "$SCRIPT_DIR"

DERIVED="$SCRIPT_DIR/.derived"
rm -rf "$DERIVED"

BUILD_LOG="$(mktemp -t macrodeck-build.XXXXXX)"
if ! xcodebuild \
        -project "$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -configuration Release \
        -derivedDataPath "$DERIVED" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build > "$BUILD_LOG" 2>&1; then
    echo "Error: xcodebuild failed. Full log:"
    cat "$BUILD_LOG"
    exit 1
fi

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "Error: build succeeded but $BUILT_APP not found. Build log:"
    cat "$BUILD_LOG"
    exit 1
fi
rm -f "$BUILD_LOG"

echo "==> Stopping any running instance..."
launchctl unload "$PLIST" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/com.mac-macro.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.mac-macro.plist"
pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
sleep 1

# Clear TCC entries so the new binary gets a clean grant (stale entries cause
# silent failures after the binary signature changes).
tccutil reset Accessibility com.macrodeck.app 2>/dev/null || true
tccutil reset ListenEvent   com.macrodeck.app 2>/dev/null || true

echo "==> Installing to $APP_DEST..."
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_DEST"
cp -R "$BUILT_APP" "$APP_DEST"

# Ad-hoc sign so the OS treats it as a stable identity for TCC grants.
codesign --force --deep --sign - "$APP_DEST" >/dev/null 2>&1 || true

echo "==> Registering LaunchAgent..."
mkdir -p "$(dirname "$PLIST")"
mkdir -p "$HOME/.mac-macro"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>Program</key>
    <string>$APP_DEST/Contents/MacOS/$APP_NAME</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

launchctl load -w "$PLIST"

echo ""
echo "  MacroDeck installed to $APP_DEST"
echo "  Registered to launch at login"
echo "  Log: $LOG"
echo ""
echo "Next: grant Accessibility + Input Monitoring to MacroDeck in"
echo "      System Settings > Privacy & Security"
