#!/bin/zsh
set -eu
cd "${0:A:h:h}"
root="$PWD"
build="$root/.build/NetMD"
export MACOSX_DEPLOYMENT_TARGET=15.0
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export ac_cv_func_pipe2=no
mkdir -p "$build/downloads"
touch "$build/build.lock"
zmodload zsh/system
zsystem flock -f buildLock "$build/build.lock"

fetch() {
    local name="$1" url="$2" checksum="$3"
    local archive="$build/downloads/$name.tar.bz2"
    if [[ ! -f "$archive" ]]; then
        [[ "${NETMD_FETCH:-0}" == 1 ]] || { print -u2 "Missing $archive; set NETMD_FETCH=1."; exit 1; }
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
        [[ -d "$sourceRoot/$name-$version" ]] || tar -xf "$build/downloads/$name.tar.bz2" -C "$sourceRoot"
        (
            cd "$sourceRoot/$name-$version"
            ./configure --build="$buildTriplet" --host="$arch-apple-darwin" \
                --prefix="$prefix" --disable-shared --enable-static "$@" &&
            make -j4 &&
            make install
        ) > "$build/$name-$arch-build.log" 2>&1 || { tail -60 "$build/$name-$arch-build.log"; exit 1; }
    fi
    xcrun lipo -verify_arch "$arch" "$prefix/lib/$library.a"
}

architectures=(${=NETMD_ARCHS:-$(uname -m)})
buildTriplet="$(uname -m)-apple-darwin"
netmdSlices=()
atracSlices=()
for arch in $architectures; do
    [[ "$arch" == arm64 || "$arch" == x86_64 ]] || { print -u2 "Unsupported architecture: $arch"; exit 1; }
    print "Building native helpers: $arch"
    prefix="$build/prefix-$arch-macos15"
    sourceRoot="$build/sources-$arch-macos15"
    objects="$build/objects-$arch-macos15"
    binaries="$build/bin-$arch-macos15"
    mkdir -p "$prefix" "$sourceRoot" "$objects" "$binaries"
    export CC="$(xcrun -f clang) -arch $arch"
    export CXX="$(xcrun -f clang++) -arch $arch"
    export CFLAGS="-arch $arch -isysroot $SDKROOT -mmacosx-version-min=15.0"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="$CFLAGS"
    compile libusb 1.0.29 --disable-dependency-tracking
    compile libgpg-error 1.55 --disable-doc --disable-nls
    compile libgcrypt 1.11.1 --disable-doc --disable-asm --with-libgpg-error-prefix="$prefix"
    for source in "$root"/Vendor/NetMD/src/*.cpp; do
        object="$objects/${source:t:r}.o"
        stale=0
        [[ -f "$object" && ! "$source" -nt "$object" ]] || stale=1
        for header in "$root"/Vendor/NetMD/{include,src}/*.(h|hpp)(N); do
            if [[ "$header" -nt "$object" ]]; then stale=1; break; fi
        done
        if [[ "$stale" == 1 ]]; then
            xcrun clang++ -arch "$arch" -std=c++17 -O2 -mmacosx-version-min=15.0 \
                -I"$prefix/include" -I"$prefix/include/libusb-1.0" \
                -I"$root/Vendor/NetMD/include" -I"$root/Vendor/NetMD/src" -c "$source" -o "$object"
        fi
    done
    xcrun clang++ -arch "$arch" -std=c++17 -fobjc-arc -O2 -mmacosx-version-min=15.0 \
        -I"$prefix/include" -I"$prefix/include/libusb-1.0" -I"$root/Vendor/NetMD/include" -I"$root/Vendor/NetMD/src" \
        "$root/Sources/NetMDHelper/main.mm" "$objects"/*.o \
        "$prefix/lib/libusb-1.0.a" "$prefix/lib/libgcrypt.a" "$prefix/lib/libgpg-error.a" \
        -framework Foundation -framework AudioToolbox -framework IOKit -framework CoreFoundation -framework Security \
        -o "$binaries/BootleggerNetMD"
    NETMD_ARCH="$arch" NETMD_SLICE_ONLY=1 zsh "$root/scripts/build-atrac.sh" \
        > "$build/atrac-$arch-build.log" 2>&1 || { tail -60 "$build/atrac-$arch-build.log"; exit 1; }
    netmdSlices+=("$binaries/BootleggerNetMD")
    atracSlices+=("$binaries/BootleggerATRAC")
done
for name in BootleggerNetMD BootleggerATRAC; do
    if [[ "$name" == BootleggerNetMD ]]; then slices=($netmdSlices); else slices=($atracSlices); fi
    if (( ${#slices} == 1 )); then cp "$slices[1]" "$build/$name"; else xcrun lipo -create $slices -output "$build/$name"; fi
    for arch in $architectures; do xcrun lipo -verify_arch "$arch" "$build/$name"; done
    if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
        destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
        mkdir -p "$destination"
        cp "$build/$name" "$destination/$name"
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$destination/$name"
    fi
done
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    sources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/NetMDSources"
    mkdir -p "$sources/Vendor" "$sources/Sources" "$sources/scripts" "$sources/.build/NetMD/downloads"
    cp -R "$root/Vendor/NetMD" "$root/Vendor/ATRACDEnc" "$sources/Vendor/"
    cp -R "$root/Sources/NetMDHelper" "$sources/Sources/"
    cp "$root/scripts/build-netmd.sh" "$root/scripts/build-atrac.sh" "$sources/scripts/"
    cp "$build"/downloads/*.(bz2|xz)(N) "$sources/.build/NetMD/downloads/"
    cp "$root/THIRD_PARTY_NOTICES.md" "$root/LICENSE" "$sources/"
fi
