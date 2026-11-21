#!/bin/zsh
# Собирает установочный образ build/wmerge-<версия>.dmg: приложение + ярлык «Программы».
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-0.1}"
./scripts/bundle.sh

STAGE=build/dmg
DMG="build/wmerge-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/WMerge.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "WMerge $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Установщик: $DMG"
