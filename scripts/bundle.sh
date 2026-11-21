#!/bin/zsh
# Собирает «WMerge.app» в build/ (без Xcode, только SwiftPM и swiftc).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/WMerge.app"
VERSION="${VERSION:-0.1}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/ru.lproj"
cp .build/release/WMerge "$APP/Contents/MacOS/WMerge"

# Иконка программы: рисуем кодом и собираем .icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc -O -o build/appicon scripts/appicon/main.swift Sources/WMerge/Shared/Theme.swift
build/appicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WMerge</string>
<key>CFBundleDisplayName</key><string>WMerge</string>
<key>CFBundleIdentifier</key><string>dev.oleg.wmerge</string>
<key>CFBundleExecutable</key><string>WMerge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>dev.oleg.wmerge.compare</string>
  <key>CFBundleURLSchemes</key><array><string>wmerge</string></array>
</dict></array>
<key>CFBundleDocumentTypes</key><array>
  <dict>
    <key>CFBundleTypeName</key><string>Text</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.text</string><string>public.data</string></array>
  </dict>
  <dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>None</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict>
</array>
<key>NSDesktopFolderUsageDescription</key><string>WMerge compares files and folders in your Desktop folder.</string>
<key>NSDocumentsFolderUsageDescription</key><string>WMerge compares files and folders in your Documents folder.</string>
<key>NSDownloadsFolderUsageDescription</key><string>WMerge compares files and folders in your Downloads folder.</string>
<key>NSRemovableVolumesUsageDescription</key><string>WMerge compares files and folders on removable drives.</string>
<key>NSNetworkVolumesUsageDescription</key><string>WMerge compares files and folders on network drives.</string>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
echo "Готово: $APP"
