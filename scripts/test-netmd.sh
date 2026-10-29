#!/bin/zsh
set -eu
cd "${0:A:h:h}"
build="$PWD/.build/NetMD"
prefix="$build/prefix-$(uname -m)-macos15"
xcrun clang++ -std=c++17 -mmacosx-version-min=15.0 -I"$prefix/include" \
    -I"$prefix/include/libusb-1.0" -IVendor/NetMD/src -ISources/NetMDHelper \
    Tests/NetMDHelperTests/main.cpp "$build/objects-$(uname -m)-macos15"/*.o \
    "$prefix/lib/libusb-1.0.a" "$prefix/lib/libgcrypt.a" "$prefix/lib/libgpg-error.a" \
    -framework IOKit -framework CoreFoundation -framework Security \
    -o "$build/NetMDTests"
"$build/NetMDTests"
