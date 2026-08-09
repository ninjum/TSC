#!/bin/bash
#
# startup-messages-test.sh - an ordinary start is quiet, and says nothing that
# looks like a fault.
#
# WHY THIS EXISTS. Running the AppImage on a normal machine, for the first time,
# printed two lines that describe nothing wrong:
#
#   Warning: Preferences file '/home/user/.config/tsc/config.xml' does not
#   exist. Using default values.
#   No joysticks available
#
# The first is on stderr and begins "Warning:", and EVERY first run reaches it -
# there is no preferences file until something is saved. So the very first thing
# a new player saw was the game reporting a problem it did not have, and any
# script capturing stderr saw the same. It is a fact on stdout now, and it still
# names the path, so the case that DOES matter - an existing preferences file
# that stopped being found - is just as visible.
#
# The second printed on almost every start, because most machines have no
# joystick, and said only that the computer is an ordinary computer. Its own
# sibling line, "Joysticks found : N", was already debug-gated - so the
# uninteresting answer was loud and the interesting one silent. Both are gated
# now.
#
# Neither is cosmetic-only in effect: real messages are worth reading, and a
# start that always prints two false alarms is a start nobody reads.
#
# Run: testing/startup-messages-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefs="$here/../tsc/src/user/preferences.cpp"
joy="$here/../tsc/src/input/joystick.cpp"

passed=0
failed=0
ok()   { echo "  ok   - $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL - $1"; failed=$((failed + 1)); }

echo "===== startup messages: an ordinary start is quiet"

for f in "$prefs" "$joy"; do
    [ -f "$f" ] || { echo "  FAIL - missing $f" >&2; exit 1; }
done

# ------------------------------------------------------- the preferences line

# The branch taken when there is no preferences file yet.
block="$(awk '/if \(!File_Exists\(filename\)\)/ {f=1} f {print} f && /^    }/ {exit}' "$prefs")"

if [ -z "$block" ]; then
    fail "could not find the 'no preferences file' branch in preferences.cpp"
else
    ok "the 'no preferences file yet' branch is still there"

    if printf '%s' "$block" | grep -q 'cerr'; then
        fail "a first run still writes to stderr"
    else
        ok "it does not write to stderr"
    fi

    # Code only: the comment above the line explains what "Warning:" used to
    # do there, and must be allowed to say the word.
    code="$(printf '%s\n' "$block" | grep -v '^[[:space:]]*//')"
    if printf '%s' "$code" | grep -qi '"Warning'; then
        fail "a first run still calls itself a Warning"
    else
        ok "and does not call itself a warning"
    fi

    # It must still SAY something, and still name the path: going silent would
    # hide a preferences file that stopped being found, which is a real fault.
    if printf '%s' "$block" | grep -q 'cout'; then
        ok "it still reports the situation, on stdout"
    else
        fail "the message was removed; a missing existing config would be silent"
    fi

    if printf '%s' "$block" | grep -q 'path_to_utf8(filename)'; then
        ok "and still names the path it looked at"
    else
        fail "the path is no longer named, so the message cannot be acted on"
    fi
fi

# ---------------------------------------------------------- the joystick line

if grep -q '"No joysticks available"' "$joy"; then
    ok "the no-joystick message still exists for debugging"

    # It must sit inside an m_debug guard - the same gate its sibling uses.
    guarded="$(awk '/m_num_joysticks == 0/ {f=1} f {print} f && /return 0;/ {exit}' "$joy" \
               | grep -c 'if (m_debug)')"
    if [ "${guarded:-0}" -ge 1 ]; then
        ok "and it is debug-gated"
    else
        fail "'No joysticks available' still prints on every ordinary start"
    fi
else
    fail "the message was deleted rather than gated; --debug should still say it"
fi

# NEGATIVE: the sibling must stay gated too. Making both loud would be the same
# mistake in the other direction.
if grep -A3 '"Joysticks found : "' "$joy" >/dev/null 2>&1 \
   && awk '/if \(m_debug\)/ {f=1} f && /Joysticks found/ {found=1} END {exit !found}' "$joy"; then
    ok "negative: the 'joysticks found' line is still debug-gated as well"
else
    fail "the 'joysticks found' line is no longer debug-gated"
fi

echo "===== startup messages: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
