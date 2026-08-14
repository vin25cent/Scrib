#!/usr/bin/env bash
set -euo pipefail

configuration="${1:-release}"
output_directory="${2:-artifacts}"
archive_stem="${3:-Scrib-unsigned}"
case "$output_directory" in
  ""|"."|"/"|/*|*".."*)
    echo "Refusing unsafe output directory: $output_directory" >&2
    exit 2
    ;;
esac
case "$archive_stem" in
  ""|*/*|*".."*)
    echo "Refusing unsafe archive name: $archive_stem" >&2
    exit 2
    ;;
esac

swift build -c "$configuration" --product ScribApp
binary_path="$(swift build -c "$configuration" --product ScribApp --show-bin-path)/ScribApp"
app_path="$output_directory/Scrib.app"
archive_path="$output_directory/$archive_stem.zip"
checksum_path="$archive_path.sha256"

test -x "$binary_path"

rm -rf "$app_path" "$archive_path" "$checksum_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/ScribApp"
cp Packaging/Info.plist "$app_path/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/"
chmod 755 "$app_path/Contents/MacOS/ScribApp"
plutil -lint "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
(cd "$output_directory" && shasum -a 256 "$archive_stem.zip" > "$archive_stem.zip.sha256")
