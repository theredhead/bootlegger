#!/bin/bash
# Freeze exact sources, build universal apps/helpers, audit redistribution materials, and create a DMG.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$root/.build/releases"
usage() {
    cat <<'HELP'
Usage: scripts/release.sh [--output-dir DIRECTORY]

Build all Release app targets, including native helpers, for arm64 AND x86_64.
Package the apps, exact corresponding source, licenses and build manifests in a DMG.
Default output: .build/releases. Requires Xcode, CMake and Python 3.9+.

Optional environment:
  NETMD_FETCH=0                 Use cached/bundled dependency source archives only.
  RELEASE_SIGN_IDENTITY=...     Installed signing identity (default: ad-hoc).
HELP
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            output="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
for tool in xcodebuild xcrun hdiutil codesign ditto plutil shasum lipo otool python3 cmake; do
    command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done
mkdir -p "$output" "$root/.build"
output="$(cd "$output" && pwd)"
work="$(mktemp -d "$root/.build/release.XXXXXX")"
package="$(mktemp -d "$output/.release-package.XXXXXX")"
cleanup() {
    local result=$?
    trap - EXIT
    rm -rf -- "$work" "$package"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export NETMD_FETCH="${NETMD_FETCH:-1}"
export NETMD_ARCHS='arm64 x86_64'
identity="${RELEASE_SIGN_IDENTITY:--}"
source="$work/source"
products="$work/products/Release"
stage="$work/image"
materials="$package/materials"
mkdir -p "$source" "$stage" "$materials"
python3 "$root/scripts/release-support.py" snapshot "$root" "$source"
echo 'Building all universal Release targets...'
xcodebuild -project "$source/Bootlegger.xcodeproj" -alltargets \
    -configuration Release -jobs 1 \
    "SYMROOT=$work/products" "OBJROOT=$work/intermediates" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" build \
    2>&1 | tee "$output/build-release.log"

python3 "$source/scripts/release-support.py" source-package "$source" "$materials"
source_archive=("$materials"/Bootlegger-source-*.tar.gz)
[[ ${#source_archive[@]} -eq 1 && -f "${source_archive[0]}" ]] || { echo 'Missing source package.' >&2; exit 1; }
mkdir -p "$stage/Corresponding Source"
cp "${source_archive[0]}" "$materials/SOURCE-MANIFEST.json" "$stage/Corresponding Source/"
ditto "$source/Licenses" "$stage/Licenses"
cp "$source/RELEASE_BUILD.md" "$stage/RELEASE_BUILD.md"
app_count=0
for app in "$products"/*.app; do
    [[ -d "$app" ]] || continue
    resources="$app/Contents/Resources"
    ditto "$source/Licenses" "$resources/Licenses"
    cp "${source_archive[0]}" "$resources/CorrespondingSource.tar.gz"
    cp "$materials/SOURCE-MANIFEST.json" "$resources/SOURCE-MANIFEST.json"
    cp "$source/RELEASE_BUILD.md" "$resources/RELEASE_BUILD.md"
    for binary in "$app/Contents/Helpers/BootleggerNetMD" "$app/Contents/Helpers/BootleggerATRAC"; do
        codesign --force --sign "$identity" "$binary"
    done
    codesign --force --options runtime --sign "$identity" "$app"
    ditto "$app" "$stage/$(basename "$app")"
    app_count=$((app_count + 1))
done
[[ $app_count -gt 0 && -d "$stage/Bootlegger.app" && -d "$stage/NetMD TX.app" ]] || {
    echo 'Both universal application products are required.' >&2; exit 1;
}
python3 "$source/scripts/release-support.py" verify "$stage" "$materials"
cp "$materials/BUILD-MANIFEST.json" "$stage/BUILD-MANIFEST.json"
version="$(plutil -extract CFBundleShortVersionString raw "$stage/Bootlegger.app/Contents/Info.plist")"
case "$version" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid release version.' >&2; exit 1 ;; esac
name="Bootlegger-$version-universal.dmg"
ln -s /Applications "$stage/Applications"
cat > "$stage/Read Me.txt" <<'README'
Drag Bootlegger and NetMD TX to Applications. Both apps and their native helpers
support Apple Silicon and Intel Macs running macOS 15 or later.

This distribution includes GPL/LGPL/BSD components. Full licenses and copyright
notices are in Licenses. Exact complete corresponding source and all dependency
source archives are in Corresponding Source and also inside each app's Resources.
See RELEASE_BUILD.md for modification, rebuilding, relinking and installation.
No additional restrictions on the rights granted by those licenses are imposed.

Keep matching source and notices available with any redistribution. When offering
binaries for download, offer their exact corresponding source equally accessibly
at no additional charge. See the bundled license texts for all applicable terms.
README

echo "Packaging $app_count universal apps and corresponding source..."
hdiutil create -volname 'Bootlegger' -srcfolder "$stage" -fs HFS+ -format UDZO "$package/$name"
hdiutil verify "$package/$name"
mv -f "$package/$name" "$output/$name"
cp "${source_archive[0]}" "$materials/SOURCE-MANIFEST.json" "$materials/BUILD-MANIFEST.json" "$output/"
(cd "$output" && shasum -a 256 "$name" "$(basename "${source_archive[0]}")" > "$name.sha256")
echo "Created: $output/$name"
echo "Corresponding source: $output/$(basename "${source_archive[0]}")"
echo "Checksums: $output/$name.sha256"
