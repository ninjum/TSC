#!/bin/bash
#
# ensure-release.sh - make sure the release these binaries are going to exists,
# and give it the notes CHANGELOG has for it.
#
# Every build workflow here attaches its binaries to a release, and until now
# each assumed one was already there: the .deb, Windows, Mac and Flatpak
# workflows attached to "the newest release" and failed outright if there was
# none, which made the first build of a new version a chicken-and-egg problem.
# They all call this instead, so a workflow can be pointed at a version that
# does not exist yet and will make it.
#
# The notes come from CHANGELOG, so a release is described by the file the
# project already keeps rather than by something typed into a form and lost.
# A version with no CHANGELOG entry still gets a release - the binaries are the
# point - with a line saying where the description should have come from.
#
# Usage: ensure-release.sh <tag> [--draft]
#   tag    e.g. v2.2.0-beta2. The version for the CHANGELOG lookup is the tag
#          without its leading v.
#
# Needs GH_TOKEN in the environment.

set -euo pipefail

tag="${1:?tag is required}"
draft=""
[ "${2:-}" = "--draft" ] && draft="--draft"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="${tag#v}"

if gh release view "$tag" >/dev/null 2>&1; then
    echo "Release $tag exists."
    # Its notes may still be missing - a release created by an earlier run of a
    # workflow that had no CHANGELOG entry to use, or created by hand. Fill them
    # in if CHANGELOG has something now and the release body is empty.
    body="$(gh release view "$tag" --json body --jq '.body' 2>/dev/null || true)"
    if [ -z "${body//[[:space:]]/}" ]; then
        if notes="$(bash "$here/changelog-notes.sh" "$version" "$here/../../CHANGELOG")"; then
            printf '%s\n' "$notes" > /tmp/release-notes.md
            gh release edit "$tag" --notes-file /tmp/release-notes.md
            echo "Filled in the notes for $tag from CHANGELOG."
        fi
    fi
    exit 0
fi

echo "Release $tag does not exist yet; creating it."

if notes="$(bash "$here/changelog-notes.sh" "$version" "$here/../../CHANGELOG")"; then
    printf '%s\n' "$notes" > /tmp/release-notes.md
    echo "Using the CHANGELOG entry for $version as the release notes."
else
    {
        echo "TSC $version"
        echo
        echo "CHANGELOG has no entry for $version yet, so this release has no"
        echo "description. Add one under a \`* Version $version.\` line and re-run"
        echo "a build workflow - it fills the notes in when it finds them."
    } > /tmp/release-notes.md
    echo "::warning::CHANGELOG has no entry for $version; the release is created without notes."
fi

# --target the commit that is being built, not whatever the branch points at by
# the time somebody looks.
gh release create "$tag" \
    --title "$tag" \
    --notes-file /tmp/release-notes.md \
    --target "${GITHUB_SHA:-HEAD}" \
    $draft

echo "Created $tag."
