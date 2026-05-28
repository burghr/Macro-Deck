#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MacroDeck"
LABEL="com.macrodeck.app"
INSTALL_DIR="$HOME/Applications"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.mac-macro/macrodeck.log"

echo "==> Building $APP_NAME (this takes ~30s)..."
cd "$SCRIPT_DIR"
rm -rf dist build
arch -arm64 /usr/bin/python3 setup.py py2app 2>&1 | grep -v "^$" | grep -E "(warning|error|Error|Done|^!)" || true

if [ ! -d "$SCRIPT_DIR/dist/$APP_NAME.app" ]; then
    echo "Error: build failed — dist/$APP_NAME.app not found"
    exit 1
fi

echo "==> Stopping any running instance..."
launchctl unload "$PLIST" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/com.mac-macro.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.mac-macro.plist"
pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
pkill -f "mac-macro/main.py" 2>/dev/null || true
sleep 1

# Clear TCC entries so the new binary gets a clean grant (stale entries cause silent failures)
tccutil reset Accessibility com.macrodeck.app 2>/dev/null || true
tccutil reset ListenEvent com.macrodeck.app 2>/dev/null || true

echo "==> Installing to $APP_DEST..."
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_DEST"
cp -r "$SCRIPT_DIR/dist/$APP_NAME.app" "$APP_DEST"

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
