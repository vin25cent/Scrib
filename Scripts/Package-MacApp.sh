#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
output_directory="${2:-artifacts}"
case "$output_directory" in
  ""|"."|"/"|/*|*".."*)
    echo "Refusing unsafe output directory: $output_directory" >&2
    exit 2
    ;;
esac

swift build -c "$configuration" --product ScribApp
binary_path="$(swift build -c "$configuration" --product ScribApp --show-bin-path)/ScribApp"
app_path="$output_directory/Scrib.app"

test -x "$binary_path"

rm -rf "$app_path" "$output_directory/Scrib-unsigned.zip" "$output_directory/Scrib-unsigned.zip.sha256"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/ScribApp"
cp Packaging/Info.plist "$app_path/Contents/Info.plist"
chmod 755 "$app_path/Contents/MacOS/ScribApp"
plutil -lint "$app_path/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_directory/Scrib-unsigned.zip"
(cd "$output_directory" && shasum -a 256 Scrib-unsigned.zip > Scrib-unsigned.zip.sha256)
