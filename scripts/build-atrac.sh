#!/bin/zsh
set -eu
cd "${0:A:h:h}"
root="$PWD"
build="$root/.build/NetMD"
prefix="$build/prefix-$(uname -m)-macos15"
export MACOSX_DEPLOYMENT_TARGET=15.0
archive="$build/downloads/libsndfile.tar.xz"
if [[ ! -f "$archive" ]]; then
    [[ "${NETMD_FETCH:-0}" == 1 ]] || { print -u2 'Run NETMD_FETCH=1 zsh scripts/build-netmd.sh to fetch encoder dependencies.'; exit 1; }
    curl --fail --location https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz -o "$archive"
fi
print "3799ca9924d3125038880367bf1468e53a1b7e3686a934f098b7e1d286cdb80e  $archive" | shasum -a 256 --check --status
cmake="$(command -v cmake || true)"
[[ -n "$cmake" ]] || cmake=/opt/homebrew/bin/cmake
[[ -x "$cmake" ]] || { print -u2 'CMake is required to build the optional ATRAC encoder.'; exit 1; }
if [[ ! -f "$prefix/lib/libsndfile.a" ]]; then
    mkdir -p "$build/atrac-sources"
    tar -xf "$archive" -C "$build/atrac-sources"
    "$cmake" -S "$build/atrac-sources/libsndfile-1.2.2" -B "$build/sndfile-build" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF \
        -DENABLE_EXTERNAL_LIBS=OFF -DENABLE_MPEG=OFF -DENABLE_CPACK=OFF
    "$cmake" --build "$build/sndfile-build" -j4
    "$cmake" --install "$build/sndfile-build"
fi
"$cmake" -S "$root/Vendor/ATRACDEnc/src" -B "$build/atrac-build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DBUILD_SHARED_LIBS=OFF \
    -DATRACDENC_PCM_IO_BACKEND=libsndfile -DLIBSNDFILE_INCLUDE_DIR="$prefix/include" \
    -DSNDFILE_LIBRARY="$prefix/lib/libsndfile.a"
"$cmake" --build "$build/atrac-build" --target atracdenc -j4
cp "$build/atrac-build/atracdenc" "$build/BootleggerATRAC"
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
    cp "$build/BootleggerATRAC" "$destination/BootleggerATRAC"
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$destination/BootleggerATRAC"
    sources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/NetMDSources"
    cp -R "$root/Vendor/ATRACDEnc" "$sources/Vendor/"
    cp "$root/scripts/build-atrac.sh" "$sources/scripts/"
    cp "$archive" "$sources/.build/NetMD/downloads/"
    cp "$build/atrac-sources/libsndfile-1.2.2/COPYING" "$sources/libsndfile-LICENSE"
fi
