#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/tests
xcrun swiftc -parse-as-library -swift-version 5 -strict-concurrency=complete \
    -module-cache-path .build/ModuleCache.noindex \
    Sources/Bootlegger/App/ProjectWindow.swift \
    Sources/Bootlegger/Artwork/*.swift \
    Sources/Bootlegger/Domain/*.swift \
    Sources/Bootlegger/Media/*.swift \
    Sources/Bootlegger/Documents/*.swift \
    Sources/Bootlegger/Views/*.swift \
    Tests/BootleggerTests/*.swift \
    -o .build/tests/BootleggerTests
.build/tests/BootleggerTests "$@"
