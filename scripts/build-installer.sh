#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
installer_dir="$project_dir/scripts/installer"
build_dir="$project_dir/.build/installer"
dist_dir="$project_dir/dist"
bundle_dir="$dist_dir/Relocate.app"

cd "$project_dir"

echo "==> Building Relocate.app (release)"
"$project_dir/scripts/package-app.sh"

if [ ! -d "$bundle_dir" ]; then
    echo "error: $bundle_dir not found after packaging" >&2
    exit 1
fi

identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle_dir/Contents/Info.plist")
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$bundle_dir/Contents/Info.plist")
pkg_identifier="$identifier.pkg"

echo "==> Preparing payload (version $version)"
rm -rf "$build_dir"
payload_dir="$build_dir/payload"
mkdir -p "$payload_dir"
ditto "$bundle_dir" "$payload_dir/Relocate.app"

component_plist="$build_dir/component.plist"
echo "==> Generating component property list"
pkgbuild --analyze --root "$payload_dir" "$component_plist"

# pkgbuild defaults a single-bundle payload to BundleIsRelocatable=true, which tells
# installd to look for a bundle with the same CFBundleIdentifier ANYWHERE on disk (via
# Launch Services) and update that copy in place instead of writing to
# --install-location. On a dev machine that's already built dist/Relocate.app with the
# same identifier, that silently "relocates" the install onto the build artifact instead
# of /Applications — the install reports success with nothing landing where expected.
# Forcing it off makes /Applications authoritative.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$component_plist"

component_pkg="$build_dir/RelocateComponent.pkg"
echo "==> Building component package"
pkgbuild \
    --root "$payload_dir" \
    --identifier "$pkg_identifier" \
    --version "$version" \
    --install-location "/Applications" \
    --scripts "$installer_dir/scripts" \
    --component-plist "$component_plist" \
    "$component_pkg"

distribution_xml="$build_dir/Distribution.xml"
echo "==> Synthesizing distribution definition"
productbuild --synthesize --package "$component_pkg" "$distribution_xml"

python3 - "$distribution_xml" "$pkg_identifier" <<'PY'
import sys

path, pkg_identifier = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()

insert = (
    '    <title>Relocate</title>\n'
    '    <welcome file="welcome.html" mime-type="text/html"/>\n'
    '    <conclusion file="conclusion.html" mime-type="text/html"/>\n'
)
marker = f'<pkg-ref id="{pkg_identifier}"/>'
idx = content.index(marker)
content = content[:idx] + insert + content[idx:]

with open(path, "w") as f:
    f.write(content)
PY

output_pkg="$dist_dir/Relocate-Installer.pkg"
echo "==> Building product installer"
productbuild \
    --distribution "$distribution_xml" \
    --resources "$installer_dir/resources" \
    --package-path "$build_dir" \
    "$output_pkg"

echo "==> Installer created at $output_pkg"

if security find-identity -v -p basic 2>/dev/null | grep -q "Developer ID Installer"; then
    echo "note: a Developer ID Installer certificate is present but was not used automatically."
    echo "Sign manually with:"
    echo "  productsign --sign \"Developer ID Installer: Your Name (TEAMID)\" \"$output_pkg\" \"$dist_dir/Relocate-Installer-signed.pkg\""
else
    echo "note: no Developer ID Installer certificate found — the .pkg is unsigned."
    echo "Gatekeeper will flag it as from an unidentified developer on first open."
    echo "Recipients can proceed via right-click > Open in Finder (the standard macOS path for unsigned installers)."
fi
