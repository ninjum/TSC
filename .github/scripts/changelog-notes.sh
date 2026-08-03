#!/bin/bash
#
# changelog-notes.sh - print the CHANGELOG entry for one version, as the release
# notes for it.
#
# CHANGELOG is in the GNU ChangeLog format the file has always used: a
# date/author header, a blank line, then tab-indented items, the first naming
# the version.
#
#     2026-08-03  Lauri Ojansivu  <x@xet7.org>
#
#             * Version 2.2.0-beta2.
#             * Misc: ...
#
# This finds the block whose version line matches, and prints its items with the
# leading tabs turned into markdown bullets, so a release page renders them as a
# list rather than one run-on paragraph. Continuation lines (two tabs) are folded
# into the bullet above them, because that is what they are - one item wrapped at
# the file's width, not a nested list.
#
# Usage: changelog-notes.sh <version> [path/to/CHANGELOG]
# Prints nothing and exits 1 if the version has no entry - the caller decides
# whether that is fatal.

set -uo pipefail

version="${1:?version is required}"
changelog="${2:-CHANGELOG}"

[ -f "$changelog" ] || { echo "changelog-notes.sh: no $changelog" >&2; exit 1; }

awk -v want="$version" '
    # A date header starts a block; the version line inside decides if it is ours.
    /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ { inblock = 0 }
    {
        if (match($0, /^\t\* Version[ \t]+/)) {
            v = $0
            sub(/^\t\* Version[ \t]+/, "", v)
            sub(/\.[ \t]*$/, "", v)
            sub(/[ \t]+released$/, "", v)
            inblock = (v == want)
            next            # the version line itself is not a release note
        }
        if (!inblock) next
        # A continuation line is indented by two tabs; fold it into the bullet.
        if (match($0, /^\t\t/)) { sub(/^\t\t/, " "); printf "%s", $0; next }
        if (match($0, /^\t\* /)) { sub(/^\t\* /, ""); printf "\n- %s", $0; next }
        if ($0 ~ /^[ \t]*$/) next
        printf " %s", $0
    }
    END { printf "\n" }
' "$changelog" | sed -e '/./,$!d' > /tmp/changelog-notes.$$

if [ ! -s /tmp/changelog-notes.$$ ]; then
    rm -f /tmp/changelog-notes.$$
    exit 1
fi

cat /tmp/changelog-notes.$$
rm -f /tmp/changelog-notes.$$
