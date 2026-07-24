#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
configuration=${CONFIGURATION:-release}
architecture=$(uname -m)
bundle_dir="$project_dir/dist/Relocate.app"
contents_dir="$bundle_dir/Contents"

cd "$project_dir"
swift build -c "$configuration"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp ".build/$architecture-apple-macosx/$configuration/Relocate" "$contents_dir/MacOS/Relocate"
cp "Resources/Info.plist" "$contents_dir/Info.plist"

iconset_dir="$project_dir/.build/Relocate.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "Resources/AppIcon.svg" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -s format png -z "$double_size" "$double_size" "Resources/AppIcon.svg" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/AppIcon.icns"

codesign --force --deep --sign - "$bundle_dir"

echo "Created $bundle_dir"
