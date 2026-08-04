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
    # Keep the notes in SYNC with CHANGELOG, every run. CHANGELOG is the source of
    # truth for the description (that is the whole point of reading them from it),
    # so re-copy its entry for this version whenever it has one - not only when the
    # release body happens to be empty. Both "Release all" (re-run) and "Release
    # all missing" complete an EXISTING release, so this is the path they take, and
    # only re-copying here is what lets a CHANGELOG edit made AFTER the release was
    # created reach the release page. Filling only an empty body left the notes
    # frozen at whatever the CHANGELOG said the first time.
    #
    # If CHANGELOG has no entry for this version, the existing notes are left as
    # they are rather than wiped - there is nothing to replace them with.
    if notes="$(bash "$here/changelog-notes.sh" "$version" "$here/../../CHANGELOG")"; then
        printf '%s\n' "$notes" > /tmp/release-notes.md
        current="$(gh release view "$tag" --json body --jq '.body' 2>/dev/null || true)"
        # Normalise CRLF the API may return before comparing, so an unchanged
        # CHANGELOG does not rewrite the body on every one of the parallel build
        # workflows that call this.
        if [ "${current//$'\r'/}" != "$notes" ]; then
            gh release edit "$tag" --notes-file /tmp/release-notes.md
            echo "Synced the notes for $tag from CHANGELOG."
        else
            echo "Notes for $tag already match CHANGELOG."
        fi
    else
        echo "CHANGELOG has no entry for $version; leaving the existing notes as they are."
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
