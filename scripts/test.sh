#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/tests
zsh scripts/build-netmd.sh > .build/tests/netmd-build.log 2>&1
zsh scripts/test-netmd.sh
export BOOTLEGGER_ATRAC_ENCODER="$PWD/.build/NetMD/BootleggerATRAC"
export BOOTLEGGER_NETMD_HELPER="$PWD/.build/NetMD/BootleggerNetMD"
xcrun swiftc -parse-as-library -swift-version 5 -strict-concurrency=complete \
    -module-cache-path .build/ModuleCache.noindex \
    Sources/Bootlegger/App/ProjectWindow.swift \
    Sources/Bootlegger/Artwork/*.swift \
    Sources/Bootlegger/Domain/*.swift \
    Sources/Bootlegger/Media/*.swift \
    Sources/NetMDTX/TXLibrary.swift \
    Sources/NetMDTX/TXExtraction.swift \
    Sources/NetMDTX/ATRACDecoder.swift \
    Sources/Bootlegger/Documents/*.swift \
    Sources/Bootlegger/Views/*.swift \
    Tests/BootleggerTests/*.swift \
    -o .build/tests/BootleggerTests
.build/tests/BootleggerTests "$@"
