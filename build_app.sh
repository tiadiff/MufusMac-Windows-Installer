#!/bin/bash
set -e

echo "🔨 Building MufusMac (Release)..."
swift build -c release

echo "📦 Creating MufusMac.app bundle..."
rm -rf MufusMac.app
mkdir -p MufusMac.app/Contents/MacOS
mkdir -p MufusMac.app/Contents/Resources

cp .build/release/MufusMac MufusMac.app/Contents/MacOS/

cat > MufusMac.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MufusMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.tiadiff.mufusmac</string>
    <key>CFBundleName</key>
    <string>MufusMac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if [ -f "Sources/MufusMac/icon.png" ]; then
    echo "🎨 Generating App Icon..."
    mkdir -p MufusMac.iconset
    sips -z 16 16     Sources/MufusMac/icon.png --out MufusMac.iconset/icon_16x16.png > /dev/null
    sips -z 32 32     Sources/MufusMac/icon.png --out MufusMac.iconset/icon_16x16@2x.png > /dev/null
    sips -z 32 32     Sources/MufusMac/icon.png --out MufusMac.iconset/icon_32x32.png > /dev/null
    sips -z 64 64     Sources/MufusMac/icon.png --out MufusMac.iconset/icon_32x32@2x.png > /dev/null
    sips -z 128 128   Sources/MufusMac/icon.png --out MufusMac.iconset/icon_128x128.png > /dev/null
    sips -z 256 256   Sources/MufusMac/icon.png --out MufusMac.iconset/icon_128x128@2x.png > /dev/null
    sips -z 256 256   Sources/MufusMac/icon.png --out MufusMac.iconset/icon_256x256.png > /dev/null
    sips -z 512 512   Sources/MufusMac/icon.png --out MufusMac.iconset/icon_256x256@2x.png > /dev/null
    sips -z 512 512   Sources/MufusMac/icon.png --out MufusMac.iconset/icon_512x512.png > /dev/null
    sips -z 1024 1024 Sources/MufusMac/icon.png --out MufusMac.iconset/icon_512x512@2x.png > /dev/null
    iconutil -c icns MufusMac.iconset -o MufusMac.app/Contents/Resources/AppIcon.icns
    rm -rf MufusMac.iconset
    
    # Inject icon into plist
    sed -i '' 's|<dict>|<dict>\n    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>|' MufusMac.app/Contents/Info.plist
fi

echo "✅ Done! MufusMac.app is ready."
