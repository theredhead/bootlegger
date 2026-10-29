#!/bin/bash
# Build every app target and package the release apps and bundled helpers together.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
output="$root/.build/releases"

usage() {
    cat <<'HELP'
Usage: scripts/release.sh [--output-dir DIRECTORY]

Build all Xcode targets in Release and package the apps on this branch in one DMG.
The default output directory is .build/releases. Run on the Mac architecture you
want to distribute (arm64 or x86_64); bundled NetMD helpers use that architecture.

Optional environment:
  NETMD_FETCH=0                 Require cached native dependency sources.
  RELEASE_SIGN_IDENTITY=...     Use an installed signing identity (default: ad-hoc).
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            output="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

for tool in xcodebuild hdiutil codesign ditto plutil shasum lipo; do
    command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done

architecture="$(uname -m)"
case "$architecture" in
    arm64|x86_64) ;;
    *) echo "Unsupported build architecture: $architecture" >&2; exit 1 ;;
esac

mkdir -p "$output" "$root/.build"
output="$(cd "$output" && pwd)"
# Use fresh build products so removed/old app targets cannot enter a release.
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
identity="${RELEASE_SIGN_IDENTITY:--}"
products="$work/products/Release"
stage="$work/image"
mkdir -p "$stage"

echo "Building all Release targets for ${architecture}..."
xcodebuild -project "$root/Bootlegger.xcodeproj" -alltargets \
    -configuration Release -jobs 1 \
    "SYMROOT=$work/products" "OBJROOT=$work/intermediates" \
    "ARCHS=$architecture" ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" build \
    2>&1 | tee "$output/build-release.log"

app_count=0
for app in "$products"/*.app; do
    [[ -d "$app" ]] || continue
    executable="$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")"
    binaries=(
        "$app/Contents/MacOS/$executable"
        "$app/Contents/Helpers/BootleggerNetMD"
        "$app/Contents/Helpers/BootleggerATRAC"
    )
    for binary in "${binaries[@]}"; do
        lipo -verify_arch "$architecture" "$binary"
    done
    codesign --verify --deep --strict "$app"
    ditto "$app" "$stage/$(basename "$app")"
    app_count=$((app_count + 1))
done
[[ $app_count -gt 0 ]] || { echo "No Release apps were built." >&2; exit 1; }
[[ -d "$stage/Bootlegger.app" ]] || { echo "Missing Release product: Bootlegger.app" >&2; exit 1; }

version="$(plutil -extract CFBundleShortVersionString raw "$stage/Bootlegger.app/Contents/Info.plist")"
case "$version" in
    ''|*[!a-zA-Z0-9._-]*) echo "Invalid release version: $version" >&2; exit 1 ;;
esac
name="Bootlegger-$version-$architecture.dmg"
ln -s /Applications "$stage/Applications"
cat > "$stage/Read Me.txt" <<'README'
Drag the included apps to Applications.

Bootlegger edits concert recordings and exports tracks to files or supported NetMD
recorders. Feature branches may include additional companion apps.

The native helpers, codecs, license notices and corresponding sources are included
inside each app. macOS 15 or later is required.
README

echo "Packaging $app_count apps..."
hdiutil create -volname 'Bootlegger' -srcfolder "$stage" \
    -fs HFS+ -format UDZO "$package/$name"
hdiutil verify "$package/$name"
# Publish only a verified image, leaving any previous release intact on failure.
mv -f "$package/$name" "$output/$name"
(cd "$output" && shasum -a 256 "$name" > "$name.sha256")
echo "Created: $output/$name"
echo "Checksum: $output/$name.sha256"
