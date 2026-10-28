#!/bin/zsh
set -eu
cd "${0:A:h}"

paths=()
for candidate in Sources Tests scripts; do
    if [[ -d "$candidate" ]]; then
        paths+=("$candidate")
    fi
done

case "${1:-check}" in
    format|check) ;;
    *) print -u2 'Usage: swift-baseline.sh [format|check]'; exit 2 ;;
esac

if (( ${#paths[@]} == 0 )); then
    print 'No first-party source directories exist yet; no Swift checks ran.'
    exit 0
fi

case "${1:-check}" in
    format)
        xcrun swift-format format --configuration .swift-format --in-place --recursive "${paths[@]}"
        ;;
    check)
        xcrun swift-format lint --configuration .swift-format --strict --recursive "${paths[@]}"
        swiftlint lint --config .swiftlint.yml --strict --no-cache
        ;;
esac
