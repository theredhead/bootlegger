#!/bin/zsh
set -eu
cd "${0:A:h:h}"
root="$PWD"
build="$root/.build/NetMD"
prefix="$build/prefix-$(uname -m)-macos15"
export MACOSX_DEPLOYMENT_TARGET=15.0
export CFLAGS="-mmacosx-version-min=15.0"
export CXXFLAGS="-mmacosx-version-min=15.0"
# SDK symbol probes can accept weak imports absent on the deployment target.
# libusb must use its portable pipe/fcntl path on macOS 15 and newer.
export ac_cv_func_pipe2=no
sourceRoot="$build/sources-$(uname -m)-macos15"
mkdir -p "$build/downloads" "$prefix" "$sourceRoot"
touch "$build/build.lock"
zmodload zsh/system
zsystem flock -f buildLock "$build/build.lock"

fetch() {
    local name="$1" url="$2" checksum="$3"
    local archive="$build/downloads/$name.tar.bz2"
    if [[ ! -f "$archive" ]]; then
        if [[ "${NETMD_FETCH:-0}" != 1 ]]; then
            print -u2 "NetMD sources missing. Run NETMD_FETCH=1 zsh scripts/build-netmd.sh first."
            exit 1
        fi
        curl --fail --location "$url" -o "$archive"
    fi
    print "$checksum  $archive" | shasum -a 256 --check --status
}
fetch libusb https://github.com/libusb/libusb/releases/download/v1.0.29/libusb-1.0.29.tar.bz2 5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85
fetch libgpg-error https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.55.tar.bz2 95b178148863f07d45df0cea67e880a79b9ef71f5d230baddc0071128516ef78
fetch libgcrypt https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.11.1.tar.bz2 24e91c9123a46c54e8371f3a3a2502f1198f2893fbfbf59af95bc1c21499b00e

compile() {
    local name="$1" version="$2"
    shift 2
    local library="$name"
    [[ "$name" == libusb ]] && library=libusb-1.0
    if [[ ! -f "$prefix/lib/$library.a" ]]; then
        tar -xf "$build/downloads/$name.tar.bz2" -C "$sourceRoot"
        (
            cd "$sourceRoot/$name-$version"
            ./configure --prefix="$prefix" --disable-shared --enable-static "$@"
            make -j4
            make install
        ) > "$build/$name-build.log" 2>&1 || { tail -40 "$build/$name-build.log"; exit 1; }
    fi
}
compile libusb 1.0.29 --disable-dependency-tracking
compile libgpg-error 1.55 --disable-doc --disable-nls
compile libgcrypt 1.11.1 --disable-doc --disable-asm --with-libgpg-error-prefix="$prefix"

mkdir -p "$build/objects"
for source in "$root"/Vendor/NetMD/src/*.cpp; do
    object="$build/objects/${source:t:r}.o"
    stale=0
    if [[ ! -f "$object" || "$source" -nt "$object" ]]; then stale=1; fi
    for header in "$root"/Vendor/NetMD/{include,src}/*.(h|hpp)(N); do
        if [[ "$header" -nt "$object" ]]; then stale=1; break; fi
    done
    if [[ "$stale" == 1 ]]; then
        xcrun clang++ -std=c++17 -O2 -mmacosx-version-min=15.0 -I"$prefix/include" \
            -I"$prefix/include/libusb-1.0" -I"$root/Vendor/NetMD/include" \
            -I"$root/Vendor/NetMD/src" -c "$source" -o "$object"
    fi
done
xcrun clang++ -std=c++17 -fobjc-arc -O2 -mmacosx-version-min=15.0 \
    -I"$prefix/include" -I"$prefix/include/libusb-1.0" -I"$root/Vendor/NetMD/include" -I"$root/Vendor/NetMD/src" \
    "$root/Sources/NetMDHelper/main.mm" "$build"/objects/*.o \
    "$prefix/lib/libusb-1.0.a" "$prefix/lib/libgcrypt.a" "$prefix/lib/libgpg-error.a" \
    -framework Foundation -framework AudioToolbox -framework IOKit -framework CoreFoundation -framework Security \
    -o "$build/BootleggerNetMD"
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
    mkdir -p "$destination"
    cp "$build/BootleggerNetMD" "$destination/BootleggerNetMD"
    identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    codesign --force --sign "${identity:--}" "$destination/BootleggerNetMD"
    sources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/NetMDSources"
    mkdir -p "$sources/Vendor" "$sources/Sources" "$sources/scripts"
    cp -R "$root/Vendor/NetMD" "$sources/Vendor/"
    cp -R "$root/Sources/NetMDHelper" "$sources/Sources/"
    cp "$root/scripts/build-netmd.sh" "$sources/scripts/"
    mkdir -p "$sources/.build/NetMD/downloads"
    cp "$build"/downloads/*.tar.bz2 "$sources/.build/NetMD/downloads/"
    cp "$root/THIRD_PARTY_NOTICES.md" "$sources/"
    cp "$sourceRoot/libusb-1.0.29/COPYING" "$sources/libusb-LICENSE"
    cp "$sourceRoot/libgpg-error-1.55/COPYING.LIB" "$sources/libgpg-error-LICENSE"
    cp "$sourceRoot/libgcrypt-1.11.1/COPYING.LIB" "$sources/libgcrypt-LICENSE"
fi

zsh "$root/scripts/build-atrac.sh" > "$build/atrac-build.log" 2>&1 || { tail -40 "$build/atrac-build.log"; exit 1; }
