#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MacroDeck"
LABEL="com.macrodeck.app"
INSTALL_DIR="$HOME/Applications"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.mac-macro/macrodeck.log"

PY=/usr/bin/python3

echo "==> Checking Python dependencies..."
MISSING=()
for mod in py2app PyQt6 pynput; do
    if ! arch -arm64 "$PY" -c "import $mod" 2>/dev/null; then
        MISSING+=("$mod")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    if ! arch -arm64 "$PY" -m pip --version >/dev/null 2>&1; then
        echo "Error: pip is not available for $PY."
        echo "       Install the Xcode Command Line Tools (xcode-select --install)"
        echo "       or bootstrap pip with: $PY -m ensurepip --user"
        exit 1
    fi
    echo "    Installing: ${MISSING[*]}"
    PIP_LOG="$(mktemp -t macrodeck-pip.XXXXXX)"
    if ! arch -arm64 "$PY" -m pip install --user "${MISSING[@]}" > "$PIP_LOG" 2>&1; then
        echo "Error: failed to install Python dependencies. Full log:"
        cat "$PIP_LOG"
        echo ""
        echo "If you see 'externally-managed-environment', you are likely using a"
        echo "non-Apple Python (e.g. Homebrew). Either use /usr/bin/python3, create"
        echo "a venv, or re-run pip with --break-system-packages."
        exit 1
    fi
    rm -f "$PIP_LOG"
fi

echo "==> Building $APP_NAME (this takes ~30s)..."
cd "$SCRIPT_DIR"
rm -rf dist build
BUILD_LOG="$(mktemp -t macrodeck-build.XXXXXX)"
if ! arch -arm64 "$PY" setup.py py2app > "$BUILD_LOG" 2>&1; then
    echo "Error: py2app build failed. Full log:"
    cat "$BUILD_LOG"
    exit 1
fi

if [ ! -d "$SCRIPT_DIR/dist/$APP_NAME.app" ]; then
    echo "Error: build completed but dist/$APP_NAME.app not found. Build log:"
    cat "$BUILD_LOG"
    exit 1
fi
rm -f "$BUILD_LOG"

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
