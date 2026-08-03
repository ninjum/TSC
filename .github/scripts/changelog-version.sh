#!/bin/bash
#
# changelog-version.sh - print the version TSC is at, read from CHANGELOG.
#
# CHANGELOG is the one place a TSC version is written down in prose, and it is
# already copied verbatim into the .deb as DEBIAN/CHANGELOG, so the release
# workflows read the number from there rather than from a second place that
# could disagree with it.
#
# The format is the GNU ChangeLog one the file has always used: a date/author
# header, then tab-indented items, the first of which names the version.
#
#     2026-08-03  Lauri Ojansivu  <x@xet7.org>
#
#             * Version 2.2.0-beta2.
#
# The topmost entry is the one being developed and says "Version unreleased.";
# it is skipped, so what this prints is the newest version that HAS a number.
# "Version 2.0.0 released." is the older spelling and means the same thing, so
# a trailing " released" is dropped too.
#
# Usage: changelog-version.sh [path/to/CHANGELOG]

set -euo pipefail

changelog="${1:-CHANGELOG}"

if [ ! -f "$changelog" ]; then
    echo "changelog-version.sh: no such file: $changelog" >&2
    exit 1
fi

version="$(
    sed -n 's/^[[:space:]]*\* Version[[:space:]]\{1,\}\(.*\)\.[[:space:]]*$/\1/p' "$changelog" |
    sed 's/[[:space:]]\{1,\}released$//' |
    grep -v -i '^unreleased$' |
    head -n 1
)"

if [ -z "$version" ]; then
    echo "changelog-version.sh: no '* Version <number>.' line in $changelog" >&2
    exit 1
fi

# A version is what goes into a git tag, a .deb Version field and a file name,
# so refuse anything that is not one rather than naming a file after a typo.
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    echo "changelog-version.sh: '$version' does not look like a version" >&2
    exit 1
fi

printf '%s\n' "$version"
