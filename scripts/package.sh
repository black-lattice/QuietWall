#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Explicitly invoked packaging only; normal editing does not build or launch the app.
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="dist/QuietWall.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/QuietWall" "$app_path/Contents/MacOS/QuietWall"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
echo "已生成 $PWD/$app_path（本机架构、临时签名，未公证）"
