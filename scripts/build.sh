#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/Bouge.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$build_dir/module-cache"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
xcrun swiftc -swift-version 6 -O -warnings-as-errors \
  -target arm64-apple-macosx13.0 -module-cache-path "$build_dir/module-cache" \
  -parse-as-library "$project_dir/Sources/Bouge.swift" "$project_dir/Sources/NotificationGuide.swift" \
  -framework AppKit -framework UserNotifications -framework ServiceManagement \
  -o "$app_dir/Contents/MacOS/Bouge"
xcrun swiftc -O -module-cache-path "$build_dir/module-cache" \
  "$project_dir/scripts/Icon.swift" -o "$build_dir/make-icon"
"$build_dir/make-icon" "$build_dir/AppIcon.iconset" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier fr.m4ks.bouge "$app_dir"
codesign --verify --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
file "$app_dir/Contents/MacOS/Bouge"
printf 'App prête : %s\n' "$app_dir"
