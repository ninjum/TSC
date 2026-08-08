#!/bin/bash
#
# run-tests.sh - compile and run TSC's standalone tests.
#
# These are the tests that need nothing but a C++ compiler: no SFML, no CEGUI,
# no boost, no display, no installed game. That is the point of them - they can
# run on any machine and in any CI job, including the packaging jobs that build
# TSC for a release, so a change to the logic they cover is caught there rather
# than in a bug report about a released binary.
#
# Environment:
#   CXX     the compiler to use (default: g++)
#   TSC_TEST_OUT  where the test binaries are built (default: ./build-tests)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/../src"
out="${TSC_TEST_OUT:-$here/build-tests}"
cxx="${CXX:-g++}"

mkdir -p "$out"

failures=0

# run_test NAME SOURCE... - compile the sources into NAME and run it.
run_test() {
    local name="$1"
    shift

    echo "===== $name: building"
    if ! "$cxx" -std=c++17 -Wall -I"$src/core/filesystem" -o "$out/$name" "$@"; then
        echo "===== $name: FAILED TO BUILD"
        failures=$((failures + 1))
        return
    fi

    echo "===== $name: running"
    if "$out/$name"; then
        echo "===== $name: passed"
    else
        echo "===== $name: FAILED"
        failures=$((failures + 1))
    fi
    echo
}

run_test data_dir_test \
    "$here/data_dir_test.cpp" \
    "$src/core/filesystem/data_dir.cpp"

# run_script NAME PATH - run a shell test suite, which needs no compiler at all.
run_script() {
    local name="$1" path="$2"

    if [ ! -f "$path" ]; then
        echo "===== $name: MISSING ($path)"
        failures=$((failures + 1))
        return
    fi

    echo "===== $name: running"
    if bash "$path"; then
        echo "===== $name: passed"
    else
        echo "===== $name: FAILED"
        failures=$((failures + 1))
    fi
    echo
}

# The release workflows' `only` input: what it accepts, and that no workflow
# hands a raw input to fromJSON, which used to stop a run from LOADING.
run_script matrix_only_test "$here/../../testing/matrix-only-test.sh"

if [ "$failures" -ne 0 ]; then
    echo "===== $failures test program(s) failed"
    exit 1
fi

echo "===== all tests passed"
