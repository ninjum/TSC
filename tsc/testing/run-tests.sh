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

# Every PNG in the game data must be at least 8 bits per channel: the image
# codec TSC ships decodes 8 and 16 only, and a 1-bit one aborted the 2.2.0-beta2
# AppImage after it had drawn its loading bar.
run_script png_bit_depth_test "$here/../../testing/png-bit-depth-test.sh"

# What the AppImage packaging script may and may not fail a release for.
run_script build_appimage_test "$here/../../testing/build-appimage-test.sh"

# A linker flag is never handed to a linker that does not have it. -Wl,--as-needed
# was applied unconditionally, and Apple's linker rejects it - so every macOS job
# died at "[203/203] Linking CXX executable tsc" and the release carried 97
# assets and no disk image.
run_script link_flags_test "$here/../../testing/link-flags-test.sh"

# macOS links the gettext library, and can find it. On Linux the gettext
# functions are in glibc so nothing needs linking; on macOS they are not in
# libSystem, and Homebrew's gettext is keg-only so it is not under
# $(brew --prefix)/lib either. Both halves failed at once, and each alone still
# fails.
run_script macos_libintl_test "$here/../../testing/macos-libintl-test.sh"

# The shipped image codec can read every PNG in the game data, greyscale
# included. CEGUI's STB codec asked stb for the file's own channel count and
# then accepted only 3 and 4, so all 38 greyscale images - one channel, or two
# with alpha - were decoded fine and thrown away, and the game drew a dummy
# image for each. png-bit-depth-test.sh passed 1029 of 1029 throughout, which
# is why this is a second test and not another check inside that one.
run_script cegui_greyscale_test "$here/../../testing/cegui-greyscale-test.sh"

# A spinner can be created at all. CEGUI's editbox validation is PCRE-only, and
# without PCRE its editboxes get NO validator - so Editbox::setValidationString,
# which every Spinner calls, threw and aborted the game the moment the Options
# menu was opened. The patch adds a std::regex matcher; this compiles it out of
# the patch and runs it against Spinner's four validation strings.
run_script cegui_regex_test "$here/../../testing/cegui-regex-test.sh"

# An ordinary start is quiet. A first run has no preferences file and most
# machines have no joystick, and both facts were reported as though something
# had gone wrong - one of them on stderr, calling itself a Warning.
run_script startup_messages_test "$here/../../testing/startup-messages-test.sh"

if [ "$failures" -ne 0 ]; then
    echo "===== $failures test program(s) failed"
    exit 1
fi

echo "===== all tests passed"
