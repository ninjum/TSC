#!/bin/bash
#
# matrix-only-test.sh - tests for .github/scripts/matrix-only.sh and for the
# entry lists the workflows hand it.
#
# The bug this pins: `only` was read in a template expression on the build job,
#
#     BUILD_THIS: ${{ inputs.only == '' || contains(fromJSON(inputs.only), matrix.arch) }}
#
# and `fromJSON` there runs while the workflow TEMPLATE is parsed. A value that
# is not JSON therefore did not fail a build, it stopped the run from loading:
#
#     The template is not valid. .github/workflows/AppImage.yml (Line: 148,
#     Col: 19): Unexpected character encountered while parsing value: v.
#
# All three AppImage architectures died at "Prepare workflow directory", and the
# publish job reported "No architecture produced an AppImage - every build job
# failed". Nothing in that message says the input was the problem.
#
# Two halves are tested: matrix-only.sh turns any spelling of `only` into valid
# JSON (or a clear error), and every workflow's entry list agrees with its own
# matrix and with expected-assets.sh - the drift that would make a valid
# selector look invalid, which after this change FAILS a run rather than
# silently building nothing.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
script="$repo/.github/scripts/matrix-only.sh"

failures=0
checks=0

ok() { checks=$((checks + 1)); echo "  ok   - $1"; }
bad() { checks=$((checks + 1)); failures=$((failures + 1)); echo "  FAIL - $1"; }

# expect_out DESCRIPTION EXPECTED ONLY [ENTRIES...]
expect_out() {
    local desc="$1" expected="$2" only="$3"
    shift 3
    local got
    got="$(bash "$script" "$only" "$@" 2>/dev/null)"
    if [ "$got" = "$expected" ]; then
        ok "$desc"
    else
        bad "$desc (expected '$expected', got '$got')"
    fi
}

# expect_fail DESCRIPTION ONLY [ENTRIES...]
expect_fail() {
    local desc="$1" only="$2"
    shift 2
    local got status
    got="$(bash "$script" "$only" "$@" 2>&1)"
    status=$?
    if [ "$status" -ne 0 ]; then
        ok "$desc"
    else
        bad "$desc (expected a non-zero exit, got 0 and '$got')"
    fi
}

ARCHS=(x86_64 aarch64 armhf)

echo "===== matrix-only.sh"

expect_out 'empty means all of them' '[]' '' "${ARCHS[@]}"
expect_out 'whitespace also means all of them' '[]' '   ' "${ARCHS[@]}"
expect_out 'a JSON array is kept' '["armhf","x86_64"]' '["armhf","x86_64"]' "${ARCHS[@]}"
expect_out 'a JSON array with spaces' '["armhf","x86_64"]' '[ "armhf", "x86_64" ]' "${ARCHS[@]}"
expect_out 'a comma-separated list' '["armhf","x86_64"]' 'armhf,x86_64' "${ARCHS[@]}"
expect_out 'a space-separated list' '["armhf","x86_64"]' 'armhf x86_64' "${ARCHS[@]}"
expect_out 'one entry' '["aarch64"]' 'aarch64' "${ARCHS[@]}"
expect_out 'a repeat is emitted once' '["armhf"]' 'armhf,armhf' "${ARCHS[@]}"
expect_out 'punctuation with no entries means all of them' '[]' ',,' "${ARCHS[@]}"
expect_out 'order is the order asked for' '["x86_64","armhf"]' 'x86_64 armhf' "${ARCHS[@]}"

# THE BUG: a version in the `only` box. It must be an error here, where the
# message says what is wrong, and never reach fromJSON.
expect_fail 'negative: a version is refused, not passed on as JSON' 'v2.2.0-beta2' "${ARCHS[@]}"
expect_fail 'negative: a typo is refused' 'aarch65' "${ARCHS[@]}"
expect_fail 'negative: one bad entry among good ones fails the whole list' 'armhf,nonsense' "${ARCHS[@]}"
expect_fail 'negative: an entry of ANOTHER workflow is refused' 'win64' "${ARCHS[@]}"
expect_fail 'negative: no valid entries given is a usage error' 'armhf'

# Whatever it prints, it is JSON: that is the property the workflows depend on.
for value in '' '   ' 'armhf' 'armhf,x86_64' '["armhf"]' ',,'; do
    out="$(bash "$script" "$value" "${ARCHS[@]}" 2>/dev/null)"
    case "$out" in
        '[]'|'['*']') ok "output for '$value' is a JSON array" ;;
        *) bad "output for '$value' is not a JSON array: '$out'" ;;
    esac
done

echo
echo "===== the workflows"

# entries_of WORKFLOW - the list the workflow hands matrix-only.sh
entries_of() {
    sed -n 's/.*matrix-only\.sh "\$IN_ONLY" \(.*\))"$/\1/p' "$repo/.github/workflows/$1"
}

for wf in AppImage.yml Deb.yml Flatpak.yml Mac.yml Windows.yml; do
    entries="$(entries_of "$wf")"
    if [ -n "$entries" ]; then
        ok "$wf normalises its \`only\` input in the version job"
    else
        bad "$wf does not call matrix-only.sh"
        continue
    fi

    # No workflow may still hand a raw input to fromJSON - that is the landmine.
    if grep -q 'fromJSON(inputs.only)' "$repo/.github/workflows/$wf"; then
        bad "$wf still calls fromJSON on the raw input"
    else
        ok "$wf: negative - no fromJSON(inputs.only) remains"
    fi

    if grep -q "contains(fromJSON(needs.version.outputs.only)" "$repo/.github/workflows/$wf"; then
        ok "$wf filters on the normalised output"
    else
        bad "$wf does not filter on needs.version.outputs.only"
    fi
done

# The selectors release-all-missing.yml can send must all be accepted, or a run
# that comes to rebuild one missing asset now FAILS instead of building it.
echo
selectors_for() {
    bash "$repo/.github/scripts/expected-assets.sh" 9.9.9 | awk -v k="$1" '$1 == k { print $2 }' | sort -u
}
# Derived assets never reach `only`: release-all-missing empties the whole list
# when one is missing (derived_deb / derived_windows / derived_mac there).
derived_re() {
    case "$1" in
        deb) printf '^scripts-' ;;
        windows) printf '^combined$' ;;
        mac) printf '^universal$' ;;
        *) printf '^$' ;;
    esac
}

check_kind() {
    local kind="$1" wf="$2"
    local entries sel
    entries="$(entries_of "$wf")"
    for sel in $(selectors_for "$kind"); do
        if printf '%s\n' "$sel" | grep -q "$(derived_re "$kind")"; then
            continue
        fi
        if bash "$script" "$sel" $entries >/dev/null 2>&1; then
            ok "$wf accepts the selector '$sel' that release-all-missing can send"
        else
            bad "$wf REJECTS '$sel', which release-all-missing sends for a missing asset"
        fi
    done
}

check_kind appimage AppImage.yml
check_kind flatpak Flatpak.yml
check_kind deb Deb.yml
check_kind mac Mac.yml
check_kind windows Windows.yml

echo
if [ "$failures" -ne 0 ]; then
    echo "===== $checks checks, $failures FAILED"
    exit 1
fi
echo "===== $checks checks, all passed"
