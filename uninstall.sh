#!/bin/bash

APP_NAME="MacroDeck"
LABEL="com.macrodeck.app"
APP_DEST="$HOME/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Remove old LaunchAgent label too
launchctl unload "$HOME/Library/LaunchAgents/com.mac-macro.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.mac-macro.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
pkill -f "mac-macro/main.py" 2>/dev/null || true

rm -rf "$APP_DEST"

echo "Uninstalled. MacroDeck will no longer start at login."
