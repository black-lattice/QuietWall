#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Explicitly invoked packaging only; normal editing does not build or launch the app.
architectures=("$(uname -m)")
if [[ "${1:-}" == "--universal" && "$#" == 1 ]]; then
    architectures=(arm64 x86_64)
elif [[ "$#" != 0 ]]; then
    echo "用法：$0 [--universal]" >&2
    exit 1
fi

binaries=()
for architecture in "${architectures[@]}"; do
    triple="$architecture-apple-macosx13.0"
    swift build -c release --triple "$triple"
    binary_dir="$(swift build -c release --triple "$triple" --show-bin-path)"
    binaries+=("$binary_dir/QuietWall")
done

app_path="dist/QuietWall.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "${#binaries[@]}" == 1 ]]; then
    cp "${binaries[0]}" "$app_path/Contents/MacOS/QuietWall"
else
    lipo -create "${binaries[@]}" -output "$app_path/Contents/MacOS/QuietWall"
fi
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
codesign --verify --strict --verbose=2 "$app_path"
lipo "$app_path/Contents/MacOS/QuietWall" -verify_arch "${architectures[@]}"
echo "已生成 ${PWD}/${app_path}（${architectures[*]}，临时签名，未公证）"
