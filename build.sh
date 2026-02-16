#!/bin/bash
set -e

echo "🔨 Building ClaudeUsageBar..."
swift build -c release 2>&1

BINARY=".build/release/ClaudeUsageBar"
APP_DIR="ClaudeUsageBar.app/Contents/MacOS"

mkdir -p "$APP_DIR"
cp "$BINARY" "$APP_DIR/ClaudeUsageBar"

# Info.plist
cat > "ClaudeUsageBar.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeUsageBar</string>
    <key>CFBundleDisplayName</key>
    <string>ClaudeUsageBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.fortivus.claude-usage-bar</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsageBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Built: ClaudeUsageBar.app"
echo "   Run: open ClaudeUsageBar.app"
