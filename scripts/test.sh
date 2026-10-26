#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed, swift-testing isn't on the
# default search paths, so point the compiler and linker at the copy the CLT ships.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FLAGS=()
if [[ "$DEV" == *CommandLineTools* ]]; then
    FRAMEWORKS="$DEV/Library/Developer/Frameworks"
    LIBS="$DEV/Library/Developer/usr/lib"
    FLAGS=(-Xswiftc -F"$FRAMEWORKS" -Xlinker -F"$FRAMEWORKS"
           -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBS")
fi

swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
