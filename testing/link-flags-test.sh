#!/bin/bash
#
# link-flags-test.sh - a linker flag is never handed to a linker that does not
# have it.
#
# WHY THIS EXISTS. tsc/CMakeLists.txt asked for -Wl,--as-needed unconditionally.
# That is a GNU ld and lld option; Apple's linker does not have it, and does not
# ignore it either:
#
#   [203/203] Linking CXX executable tsc
#   ld: unknown options: --as-needed
#   clang++: error: linker command failed with exit code 1
#
# All three macOS jobs - macOS 15 x86_64, macOS 15 arm64, macOS 26 arm64 - died
# at the very last step, after compiling all 203 objects, so the failure cost a
# full build every time and looked like a code problem rather than a one-word
# flag. The release ended up with 97 assets and no disk image at all.
#
# The flag is a CHECK, not something the game needs: it makes the Linux build
# behave like the Win32 one so over-linking is found early. So the fix is to ask
# the linker whether it takes the flag - by linking with it - instead of
# deciding from the platform, and to fall back to Apple's -dead_strip_dylibs,
# which trims unreferenced dylibs the same way.
#
# This checks BOTH halves:
#   1. by reading CMakeLists.txt   - no -Wl, flag is applied unconditionally;
#   2. by RUNNING cmake           - a flag this linker rejects is not applied,
#                                   and the build still succeeds.
# (2) is skipped when there is no cmake or no C++ compiler, which is the case in
# some packaging containers; (1) always runs, and (1) is the half that would
# have caught the bug.
#
# Run: testing/link-flags-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmakelists="$here/../tsc/CMakeLists.txt"

passed=0
failed=0

ok()   { echo "  ok   - $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL - $1"; failed=$((failed + 1)); }

echo "===== linker flags: never given to a linker that lacks them"

if [ ! -f "$cmakelists" ]; then
    echo "  FAIL - no tsc/CMakeLists.txt at $cmakelists" >&2
    exit 1
fi

# ---------------------------------------------------------------- 1. the source

# Every line that puts a -Wl, flag on the target. Comments do not count: the
# explanation above the code quotes the flag by name, and must be able to.
applied="$(grep -n 'LINK_FLAGS' "$cmakelists" | grep -v '^\s*[0-9]*:\s*#' || true)"

if [ -z "$applied" ]; then
    fail "nothing applies LINK_FLAGS any more - this test is checking nothing"
else
    ok "the linker flag is still applied somewhere"
fi

# The bug, exactly: a literal -Wl,<flag> written straight into the property.
if printf '%s\n' "$applied" | grep -q -- '-Wl,'; then
    fail "a -Wl, flag is applied literally, so it goes to every linker:"
    printf '%s\n' "$applied" | grep -- '-Wl,' | sed 's/^/         /'
else
    ok "no -Wl, flag is written literally into LINK_FLAGS"
fi

# It must come from the detection instead.
if printf '%s\n' "$applied" | grep -q 'TSC_LINK_TRIM_FLAG'; then
    ok "it comes from the flag the linker was asked about"
else
    fail "LINK_FLAGS is set from something other than the detected flag"
fi

# The detection has to actually LINK to be a detection: a compile-only check
# would pass for a flag the linker later refuses, which is this exact bug.
if grep -q 'check_cxx_source_compiles' "$cmakelists" \
   && grep -q 'CMAKE_REQUIRED_FLAGS' "$cmakelists"; then
    ok "the check links with the flag rather than guessing from the platform"
else
    fail "no link-time check of the flag"
fi

# NEGATIVE: the platform must not be what decides it. `if (APPLE)` would look
# like it works and be wrong for lld on a Mac, and for a cross-build.
#
# Read the detection BLOCK, not a window of N lines around a match: the
# `if (WIN32)` that links iconv/intl/ws2_32 sits a few lines below and has
# nothing to do with this, and a -A20 window swept it up.
block="$(awk '/include\(CheckCXXSourceCompiles\)/ { inside = 1 }
              inside { print }
              inside && /LINK_FLAGS/ { exit }' "$cmakelists")"

if [ -z "$block" ]; then
    fail "could not find the detection block at all"
elif printf '%s\n' "$block" | grep -qE '^[[:space:]]*(if|elseif)[[:space:]]*\([[:space:]]*(NOT[[:space:]]+)?(APPLE|WIN32|UNIX|MSVC|CMAKE_SYSTEM_NAME)'; then
    fail "the flag is chosen from the platform, not from the linker:"
    printf '%s\n' "$block" | grep -nE '(APPLE|WIN32|UNIX|MSVC|CMAKE_SYSTEM_NAME)' | sed 's/^/         /'
else
    ok "negative: the platform does not decide which flag is used"
fi

# Apple's linker needs the fallback to be there at all.
if grep -q -- '-dead_strip_dylibs' "$cmakelists"; then
    ok "Apple's equivalent is offered as a fallback"
else
    fail "no -dead_strip_dylibs fallback, so macOS trims nothing"
fi

# A linker with neither must not fail the build - the flag is a check, not a
# requirement.
if grep -q 'message(STATUS' "$cmakelists" \
   && ! grep -B2 -A8 'TSC_LINK_TRIM_FLAG' "$cmakelists" | grep -q 'message(FATAL_ERROR'; then
    ok "a linker with neither flag is a log line, not a failed build"
else
    fail "a linker with neither flag fails the build"
fi

# ------------------------------------------------------------- 2. run it for real

if ! command -v cmake >/dev/null 2>&1; then
    echo "  --   cmake is not installed; skipping the live check"
elif ! command -v c++ >/dev/null 2>&1 && ! command -v g++ >/dev/null 2>&1; then
    echo "  --   no C++ compiler; skipping the live check"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    echo 'int main(void) { return 0; }' > "$tmp/main.cpp"

    # The same block as tsc/CMakeLists.txt, with the candidate list injectable so
    # the "this linker refuses it" case can be exercised on THIS machine - which
    # is what a Mac does with --as-needed.
    cat > "$tmp/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.5)
project(linkflags CXX)
add_executable(tsc main.cpp)
if (NOT DEFINED TSC_TEST_FLAGS)
  set(TSC_TEST_FLAGS "-Wl,--as-needed" "-Wl,-dead_strip_dylibs")
endif()
include(CheckCXXSourceCompiles)
foreach(_tsc_link_flag ${TSC_TEST_FLAGS})
  if (NOT DEFINED TSC_LINK_TRIM_FLAG)
    string(MAKE_C_IDENTIFIER "TSC_LINKER_ACCEPTS${_tsc_link_flag}" _tsc_link_var)
    set(_tsc_saved_flags "${CMAKE_REQUIRED_FLAGS}")
    set(CMAKE_REQUIRED_FLAGS "${CMAKE_REQUIRED_FLAGS} ${_tsc_link_flag}")
    check_cxx_source_compiles("int main(void) { return 0; }" ${_tsc_link_var})
    set(CMAKE_REQUIRED_FLAGS "${_tsc_saved_flags}")
    if (${_tsc_link_var})
      set(TSC_LINK_TRIM_FLAG "${_tsc_link_flag}")
    endif()
  endif()
endforeach()
if (DEFINED TSC_LINK_TRIM_FLAG)
  message(STATUS "TRIM_WITH=${TSC_LINK_TRIM_FLAG}")
  set_property(TARGET tsc APPEND PROPERTY LINK_FLAGS "${TSC_LINK_TRIM_FLAG}")
else()
  message(STATUS "TRIM_WITH=none")
endif()
CMAKE

    # configure_case NAME [-DTSC_TEST_FLAGS=...] - print what it chose.
    configure_case() {
        local dir="$tmp/$1"; shift
        rm -rf "$dir"
        cmake -S "$tmp" -B "$dir" "$@" 2>&1 | sed -n 's/^-- TRIM_WITH=//p'
    }

    # A: the real candidate list. This machine's linker is GNU ld, so it must
    # settle on --as-needed and build.
    got="$(configure_case a)"
    if [ "$got" = "-Wl,--as-needed" ]; then
        ok "live: GNU ld is given --as-needed"
    else
        fail "live: expected --as-needed here, got '${got:-<nothing>}'"
    fi
    if cmake --build "$tmp/a" >/dev/null 2>&1; then
        ok "live: and it links"
    else
        fail "live: the chosen flag broke the link"
    fi

    # B: THE MACOS CASE, MIRRORED. Offer only the flag this linker does not
    # have. On a Mac that is --as-needed; here it is -dead_strip_dylibs. Either
    # way the flag must be dropped, not passed on - and the build must survive,
    # because the flag is a check and not a requirement.
    got="$(configure_case b -DTSC_TEST_FLAGS=-Wl,-dead_strip_dylibs)"
    if [ "$got" = "none" ]; then
        ok "live: a flag this linker refuses is dropped, not passed on"
    else
        fail "live: expected the refused flag to be dropped, got '${got:-<nothing>}'"
    fi
    if cmake --build "$tmp/b" >/dev/null 2>&1; then
        ok "live: and the build still succeeds without it"
    else
        fail "live: dropping the flag broke the build"
    fi

    # C: negative. A flag no linker on earth has must never be applied. If this
    # one comes back as chosen, the check is rubber-stamping everything and
    # cases A and B prove nothing.
    got="$(configure_case c -DTSC_TEST_FLAGS=-Wl,--definitely-not-a-real-linker-flag)"
    if [ "$got" = "none" ]; then
        ok "live: negative - an invented flag is never chosen"
    else
        fail "live: an invented flag was accepted ('$got'); the check tests nothing"
    fi
fi

echo "===== link flags: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
