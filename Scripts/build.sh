#!/bin/sh
# build.sh — one-click build for MacPorts
#
# Pipeline: unit tests -> debug build (run immediately) -> release packaging
#           (universal .app + versioned .zip/.dmg; ad-hoc sign; delegates to
#            Scripts/make-app.sh)
#
# Usage:
#   sh Scripts/build.sh                 # full pipeline
#   sh Scripts/build.sh --no-tests      # skip unit tests
#   sh Scripts/build.sh --no-app        # skip .app packaging (dev builds only)
#   sh Scripts/build.sh --app-only      # only release packaging (no tests/debug)
#
# Outputs:
#   .build/debug/MacPortsUI             # debug binary: ./run with MPUI_DEMO=...
#   dist/MacPorts.app                   # ad-hoc signed universal app
#   dist/MacPorts-v<VERSION>.zip        # release zip
#   dist/MacPorts-v<VERSION>.dmg        # release dmg

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

run_tests=1
build_debug=1
build_app=1
app_only=0

for arg in "$@"; do
    case "$arg" in
        --no-tests)  run_tests=0 ;;
        --no-app)    build_app=0 ;;
        --app-only)  app_only=1 ;;
        -h|--help)
            sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

if [ "$app_only" -eq 1 ]; then
    run_tests=0; build_debug=0; build_app=1
fi

step() { echo; echo "[$1/3] $2"; }

if [ "$run_tests" -eq 1 ]; then
    step 1 "swift test"
    swift test 2>&1 | tail -5
else
    step 1 "tests skipped (--no-tests)"
fi

if [ "$build_debug" -eq 1 ]; then
    step 2 "swift build (debug)"
    swift build 2>&1 | tail -3
    echo "    debug binary: .build/debug/MacPortsUI"
    echo "    run:          ./.build/debug/MacPortsUI"
    echo "    demo:         MPUI_DEMO=graph ./.build/debug/MacPortsUI"
else
    step 2 "debug build skipped"
fi

if [ "$build_app" -eq 1 ]; then
    step 3 "release .app (Scripts/make-app.sh)"
    sh Scripts/make-app.sh
else
    step 3 ".app packaging skipped (--no-app)"
fi

echo
echo "All requested steps done."
