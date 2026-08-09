#!/bin/bash
#
# macos-libintl-test.sh - macOS links the gettext library, and can find it.
#
# WHY THIS EXISTS. After the --as-needed fix let the macOS build reach the
# linker at all, all three macOS jobs ended there instead:
#
#   "_libintl_ngettext", referenced from:
#       TSC::cEditor::replace_sprites() in editor.cpp.o
#   "_libintl_setlocale", referenced from: TSC::I18N_Init() in i18n.cpp.o
#   "_libintl_textdomain", referenced from: TSC::I18N_Init() in i18n.cpp.o
#   ld: symbol(s) not found for architecture arm64
#
# TWO separate reasons, and fixing either alone still fails:
#
#   1. NOT LINKED. On Linux the gettext functions are IN glibc, so nothing has
#      to be linked and nobody notices. On macOS they are not in libSystem.
#      CMakeLists.txt linked -lintl on WIN32 and on the BSDs; macOS fell into
#      the plain else-branch and linked neither iconv nor intl.
#
#   2. NOT FINDABLE. Homebrew's gettext is KEG-ONLY - macOS ships a BSD gettext
#      of its own, so Homebrew refuses to shadow it - which means
#      `brew install gettext` does NOT symlink libintl into
#      $(brew --prefix)/lib. That was the only prefix on CMAKE_PREFIX_PATH, so
#      find_library(intl) came back empty for a library that had been installed
#      the whole time, in a directory nothing was looking in.
#
# Both halves are checked here, from the source, plus - where cmake and a
# compiler exist - a LIVE reproduction of the keg-only shape: a libintl that is
# present but not on any default search path is NOT found without its prefix
# and IS found with it. That is the whole bug in two cmake runs, on any OS.
#
# Run: testing/macos-libintl-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmakelists="$here/../tsc/CMakeLists.txt"
macyml="$here/../.github/workflows/Mac.yml"
findmod="$here/../tsc/cmake/modules/FindLibIntl.cmake"

passed=0
failed=0
ok()   { echo "  ok   - $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL - $1"; failed=$((failed + 1)); }

echo "===== macOS gettext: linked, and findable"

for f in "$cmakelists" "$macyml" "$findmod"; do
    [ -f "$f" ] || { echo "  FAIL - missing $f" >&2; exit 1; }
done

# ------------------------------------------------------------ 1. it is linked

# The branch that resolves iconv/intl must cover APPLE, not only the BSDs.
if grep -qE '^\s*if \(CMAKE_SYSTEM_NAME MATCHES "BSD" OR APPLE\)' "$cmakelists"; then
    ok "the iconv/intl branch covers macOS as well as the BSDs"
else
    fail "macOS does not reach find_package(LibIntl); it links no gettext"
fi

if grep -q 'target_link_libraries(tsc ${Iconv_LIBRARIES} ${LIBINTL_LIBRARIES})' "$cmakelists"; then
    ok "and it links what those found"
else
    fail "the found libraries are not linked"
fi

# NEGATIVE: a bare -lintl is what this replaced. It asks the linker to search
# its own default path, which is exactly where a keg-only library is not.
if grep -qE 'target_link_libraries\(tsc[^)]*[^_]intl' "$cmakelists" \
   | grep -v 'WIN32' >/dev/null 2>&1; then
    :
fi
if grep -nE '^\s*target_link_libraries\(tsc iconv intl' "$cmakelists" >/dev/null; then
    # This one is the WIN32 line and is fine - MinGW resolves them normally.
    if grep -B3 -nE '^\s*target_link_libraries\(tsc iconv intl' "$cmakelists" | grep -q 'if (WIN32)'; then
        ok "negative: the only bare -lintl left is the WIN32 one"
    else
        fail "a bare -lintl outside the WIN32 branch"
    fi
fi

# ---------------------------------------------------------- 2. it is findable

# The CMakeLists calls it through a find_program result, so match the
# arguments rather than the literal `brew --prefix gettext`.
if grep -q -- '--prefix gettext' "$cmakelists"; then
    ok "CMakeLists asks brew where the keg-only gettext is"
else
    fail "nothing tells cmake where a keg-only gettext lives"
fi

if grep -q 'brew --prefix gettext' "$macyml"; then
    ok "and the workflow puts that prefix on CMAKE_PREFIX_PATH"
else
    fail "the workflow still passes only \$(brew --prefix)"
fi

if grep -q 'brew install .*gettext\|gettext' "$macyml"; then
    ok "gettext is installed in the first place"
else
    fail "gettext is not installed by the macOS job"
fi

# The reason has to survive, or the next person deletes the odd-looking lines.
if grep -qi 'keg-only' "$cmakelists" && grep -qi 'keg-only' "$macyml"; then
    ok "both places say WHY the extra prefix is needed"
else
    fail "the keg-only reason is not written down"
fi

# ------------------------------------------------- 3. reproduce it for real

if ! command -v cmake >/dev/null 2>&1; then
    echo "  --   cmake is not installed; skipping the live reproduction"
elif ! command -v gcc >/dev/null 2>&1 && ! command -v cc >/dev/null 2>&1; then
    echo "  --   no C compiler; skipping the live reproduction"
else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/keg/lib" "$tmp/keg/include" "$tmp/proj"

    # A libintl that EXISTS but is on no default search path - a keg, in one
    # directory. Built as a shared library so find_library has something real.
    printf 'char *libintl_textdomain(const char *d) { (void)d; return 0; }\n' > "$tmp/intl.c"
    cat > "$tmp/keg/include/libintl.h" <<'HDR'
#ifdef __cplusplus
extern "C" {
#endif
char *libintl_textdomain(const char *d);
#ifdef __cplusplus
}
#endif
HDR
    cc="$(command -v gcc || command -v cc)"
    soext="so"; [ "$(uname -s)" = "Darwin" ] && soext="dylib"
    if ! "$cc" -shared -fPIC -o "$tmp/keg/lib/libintl.$soext" "$tmp/intl.c" 2>/dev/null; then
        echo "  --   could not build the fixture library; skipping"
    else
        cp "$findmod" "$tmp/proj/"
        printf '#include <libintl.h>\nint main(void) { return libintl_textdomain("x") ? 1 : 0; }\n' \
            > "$tmp/proj/main.cpp"
        cat > "$tmp/proj/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.5)
project(t CXX)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}")
add_executable(tsc main.cpp)
find_package(LibIntl REQUIRED)
target_include_directories(tsc PRIVATE ${LIBINTL_INCLUDE_DIRS})
target_link_libraries(tsc ${LIBINTL_LIBRARIES})
CMAKE

        # A: the runner's situation. The keg is not on the prefix path, so the
        # REQUIRED find must fail - if this passes, the machine has a libintl
        # elsewhere and the case cannot be reproduced here.
        if cmake -S "$tmp/proj" -B "$tmp/a" >/dev/null 2>&1; then
            echo "  --   this machine has a libintl on its default path; skipping A/B"
        else
            ok "live: a keg-only libintl is NOT found without its prefix"

            if cmake -S "$tmp/proj" -B "$tmp/b" \
                 -DCMAKE_PREFIX_PATH="$tmp/keg" >/dev/null 2>&1; then
                ok "live: and IS found once its prefix is on CMAKE_PREFIX_PATH"
            else
                fail "live: adding the keg prefix did not make it findable"
            fi
            if cmake --build "$tmp/b" >/dev/null 2>&1; then
                ok "live: and the executable links against it"
            else
                fail "live: found but did not link"
            fi
        fi
    fi
fi

echo "===== macOS gettext: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
