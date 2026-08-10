#!/bin/bash
#
# cegui-regex-test.sh - a spinner can be created, which means the Options menu
# opens instead of aborting the game.
#
# WHY THIS EXISTS. The 2.2.0-beta2 aarch64 AppImage started, drew its menu, and
# died the moment "Options" was clicked:
#
#   CEGUI::InvalidRequestException in function
#   'void CEGUI::Editbox::setValidationString(const CEGUI::String&)'
#   (cegui/src/widgets/Editbox.cpp:161) : Unable to set validation string on
#   Editbox 'game_spinner_camera_hor_speed/__auto_editbox__' because it does not
#   currently have a RegexMatcher validator.
#   terminate called after throwing an instance of 'CEGUI::InvalidRequestException'
#
# The chain, all of it in CEGUI:
#
#   * Editbox's validator comes from System::createRegexMatcher(), which is
#     #ifdef CEGUI_HAS_PCRE_REGEX ... #else return 0.
#   * CEGUI's CMakeLists defaults that option to ${PCRE_FOUND} - so a build on a
#     machine with no PCRE development package silently produces a library whose
#     editboxes have NO validator, and says nothing about it.
#   * Spinner::setTextInputMode() calls Editbox::setValidationString() for each
#     of its four input modes, and that method THROWS when there is no
#     validator.
#
# So every spinner aborted the application, and the Options menu is made of
# spinners. Nothing in the build was broken; nothing warned; the game shipped.
#
# THE FIX is cegui-std-regex.patch, applied by ProvideCEGUI.cmake: it adds a
# RegexMatcher implemented with std::regex and returns it on the no-PCRE path,
# so validation works with no external library on any platform. ProvideCEGUI
# also pins -DCEGUI_HAS_PCRE_REGEX=OFF, so every build takes that one path
# rather than depending on what happens to be installed - PCRE 1 is
# end-of-life, MSYS2 no longer packages it for mingw at all, and Homebrew has
# deprecated it, so "whatever is installed" was never going to stay the same
# across the four platforms TSC releases for.
#
# WHAT THIS CHECKS. The patch exists, is a real unified diff, adds the matcher
# and rewires System.cpp; ProvideCEGUI applies it and pins the option. Then the
# part that matters: the matcher's own code is extracted FROM THE PATCH,
# compiled and run against the four validation strings CEGUI's Spinner sets, so
# what is tested is the code that ships rather than a copy of it.
#
# Run: testing/cegui-regex-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/.."
patchfile="$root/cegui-std-regex.patch"
provide="$root/tsc/cmake/modules/ProvideCEGUI.cmake"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
ok()   { echo "  ok   - $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL - $1"; failed=$((failed + 1)); }

echo "===== CEGUI regex: a spinner can be created"

# ------------------------------------------------------------- the patch exists

if [ -f "$patchfile" ]; then
    ok "cegui-std-regex.patch is present"
else
    fail "cegui-std-regex.patch is missing; every spinner aborts the game"
    echo "===== CEGUI regex: $passed passed, $((failed + 1)) failed"
    exit 1
fi

for f in cegui/include/CEGUI/StdRegexMatcher.h cegui/src/StdRegexMatcher.cpp; do
    if grep -q -- "^+++ b/$f" "$patchfile"; then
        ok "it adds $f"
    else
        fail "the patch does not add $f"
    fi
done

if grep -q -- "^--- a/cegui/src/System.cpp" "$patchfile" &&
   grep -q -- "^+++ b/cegui/src/System.cpp" "$patchfile"; then
    ok "and it rewires System.cpp"
else
    fail "the patch does not touch System.cpp, so nothing would use the matcher"
fi

# The no-PCRE branch must RETURN the new matcher. A patch that adds the class
# and leaves `return 0` in place changes nothing at all.
if grep -q '^+.*return CEGUI_NEW_AO StdRegexMatcher();' "$patchfile"; then
    ok "the no-PCRE branch returns a StdRegexMatcher"
else
    fail "System::createRegexMatcher() still returns 0 without PCRE"
fi

if grep -q '^@@' "$patchfile"; then
    ok "and it is a unified diff with hunks"
else
    fail "the patch has no hunks"
fi

# ------------------------------------------------- ProvideCEGUI applies and pins

if grep -q 'cegui-std-regex.patch' "$provide"; then
    ok "ProvideCEGUI.cmake applies it"
else
    fail "ProvideCEGUI.cmake never applies the patch"
fi

if grep -q -- '-DCEGUI_HAS_PCRE_REGEX=OFF' "$provide"; then
    ok "and pins CEGUI_HAS_PCRE_REGEX=OFF, so every platform takes one path"
else
    fail "CEGUI_HAS_PCRE_REGEX is left to default to whatever PCRE is installed"
fi

# ------------------------------------------- the matcher itself, compiled and run

extract_added() {
    # The lines a new-file hunk adds, with the leading '+' removed.
    awk -v want="+++ b/$1" '
        $0 == want { infile = 1; next }
        infile && /^--- / { infile = 0 }
        infile && /^@@/ { next }
        infile && /^\+/ { print substr($0, 2) }
    ' "$patchfile"
}

extract_added cegui/include/CEGUI/StdRegexMatcher.h > "$work/StdRegexMatcher.h"
extract_added cegui/src/StdRegexMatcher.cpp        > "$work/StdRegexMatcher.cpp"

if [ -s "$work/StdRegexMatcher.h" ] && [ -s "$work/StdRegexMatcher.cpp" ]; then
    ok "the matcher's source can be read out of the patch"
else
    fail "could not extract the matcher's source from the patch"
    echo "===== CEGUI regex: $passed passed, $failed failed"
    exit 1
fi

cxx="${CXX:-g++}"
if ! command -v "$cxx" >/dev/null 2>&1; then
    echo "  skip - no $cxx here; the compile-and-run part needs a C++ compiler"
    echo "===== CEGUI regex: $passed passed, $failed failed"
    [ "$failed" -eq 0 ] || exit 1
    exit 0
fi

# CEGUI's String, Exceptions and RegexMatcher are stubbed to the parts the
# matcher uses, so this needs no CEGUI build: what is under test is the
# matcher's own logic against std::regex.
sed -e '/#include "CEGUI\/StdRegexMatcher.h"/d' -e '/#include "CEGUI\/Exceptions.h"/d' \
    "$work/StdRegexMatcher.cpp" > "$work/body.inc.tmp"
sed -n '/^class StdRegexMatcher/,/^};/p' "$work/StdRegexMatcher.h" > "$work/decl.inc.tmp"
{ echo "namespace CEGUI {"; cat "$work/decl.inc.tmp"; echo "}"; cat "$work/body.inc.tmp"; } \
    > "$work/StdRegexMatcher.body.inc"

cat > "$work/matcher_test.cpp" <<'CPP'
#include <string>
#include <stdexcept>
#include <iostream>
#include <regex>

namespace CEGUI {
  typedef std::string String;
  struct InvalidRequestException : std::runtime_error {
    InvalidRequestException(const std::string& m) : std::runtime_error(m) {}
  };
  #define CEGUI_THROW(x) throw x
  class RegexMatcher {
  public:
    enum MatchState { MS_VALID, MS_INVALID, MS_PARTIAL };
    virtual ~RegexMatcher() {}
    virtual void setRegexString(const String&) = 0;
    virtual const String& getRegexString() const = 0;
    virtual MatchState getMatchStateOfString(const String&) const = 0;
  };
}
#include "StdRegexMatcher.body.inc"

using namespace CEGUI;
static int failures = 0;
static void check(bool cond, const std::string& what) {
  std::cout << (cond ? "    ok   - " : "    FAIL - ") << what << "\n";
  if (!cond) failures++;
}

int main() {
  StdRegexMatcher m;

  // Spinner::FloatValidator, and every intermediate string a person types on
  // the way to a number. Each one must be accepted, or the editbox refuses the
  // keystroke and the spinner cannot be typed into.
  m.setRegexString("-?\\d*\\.?\\d*");
  check(m.getRegexString() == "-?\\d*\\.?\\d*", "the regex string is kept");
  const char* typed[] = {"", "-", "1", "12", "1.", "1.5", "-0.25"};
  for (const char* s : typed)
    check(m.getMatchStateOfString(s) == RegexMatcher::MS_VALID,
          std::string("float validator accepts '") + s + "'");
  const char* junk[] = {"a", "1a", "1.2.3", " 1"};
  for (const char* s : junk)
    check(m.getMatchStateOfString(s) == RegexMatcher::MS_INVALID,
          std::string("float validator rejects '") + s + "'");

  m.setRegexString("-?\\d*");           // Spinner::IntegerValidator
  check(m.getMatchStateOfString("-42") == RegexMatcher::MS_VALID, "integer accepts -42");
  check(m.getMatchStateOfString("4.2") == RegexMatcher::MS_INVALID, "integer rejects 4.2");

  m.setRegexString("[0-9a-fA-F]*");     // Spinner::HexValidator
  check(m.getMatchStateOfString("deadBEEF") == RegexMatcher::MS_VALID, "hex accepts deadBEEF");
  check(m.getMatchStateOfString("xyz") == RegexMatcher::MS_INVALID, "hex rejects xyz");

  m.setRegexString("[0-7]*");           // Spinner::OctalValidator
  check(m.getMatchStateOfString("0755") == RegexMatcher::MS_VALID, "octal accepts 0755");
  check(m.getMatchStateOfString("8") == RegexMatcher::MS_INVALID, "octal rejects 8");

  // The negatives: a bad expression throws the same exception PCRERegexMatcher
  // throws, and leaves the object in a state that refuses to answer rather than
  // answering wrongly.
  bool threw = false;
  try { m.setRegexString("[unterminated"); } catch (const InvalidRequestException&) { threw = true; }
  check(threw, "a bad regex throws InvalidRequestException");
  check(m.getRegexString().empty(), "and leaves no regex string behind");
  threw = false;
  try { m.getMatchStateOfString("1"); } catch (const InvalidRequestException&) { threw = true; }
  check(threw, "and matching against it throws rather than answering");

  return failures ? 1 : 0;
}
CPP

if "$cxx" -std=c++11 -Wall -I"$work" -o "$work/matcher_test" "$work/matcher_test.cpp" 2>"$work/cc.log"; then
    ok "the matcher compiles"
    if "$work/matcher_test"; then
        ok "and answers every Spinner validation string correctly"
    else
        fail "the matcher's own checks failed (see above)"
    fi
else
    fail "the matcher does not compile:"
    sed 's/^/      /' "$work/cc.log"
fi

echo "===== CEGUI regex: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
