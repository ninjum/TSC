#!/bin/bash
#
# matrix-only.sh - turn a workflow's `only` input into a JSON array, safely.
#
# WHY THIS EXISTS. Every release workflow can be told to build only some of its
# matrix entries, and each one used to ask that question in a template
# expression on the job itself:
#
#     BUILD_THIS: ${{ inputs.only == '' || contains(fromJSON(inputs.only), matrix.arch) }}
#
# `fromJSON` on a value the workflow does not control is a landmine, because it
# is evaluated while the workflow TEMPLATE is being parsed - before any step, and
# for every matrix entry at once. Hand it something that is not JSON and the run
# does not fail a build, it fails to load:
#
#     The template is not valid. .github/workflows/AppImage.yml (Line: 148,
#     Col: 19): Unexpected character encountered while parsing value: v.
#
# which is what happened when a dispatch put a version (`v2.2.0-beta2`) in the
# `only` box: all three AppImage jobs died at "Prepare workflow directory", the
# publish job then reported "No architecture produced an AppImage - every build
# job failed", and the message pointed at a line that looks perfectly fine.
#
# So the question is answered HERE, in a shell, where a wrong value is an error
# message instead of a parse failure - and the workflows compare against THIS
# output, which is always valid JSON, so `fromJSON` can no longer throw.
#
# WHAT IT ACCEPTS. Empty means all of them. Otherwise a list of matrix entries,
# in whichever of these a person or a workflow happens to write:
#
#     ["armhf","x86_64"]      the JSON array the workflow_call callers pass
#     armhf,x86_64            a comma-separated list
#     armhf x86_64            a space-separated list
#
# Usage:  matrix-only.sh "<only input>" <valid entry> [<valid entry> ...]
# Prints: a JSON array - [] for "all of them", or the entries that were asked for
# Exits:  non-zero, with a message naming the valid entries, if one is unknown

set -euo pipefail

only="${1-}"
shift || true

if [ "$#" -eq 0 ]; then
    echo "matrix-only.sh: no valid entries given" >&2
    exit 2
fi
valid=("$@")

# Nothing asked for: build everything. `[]` is the answer the workflows compare
# against, and it is valid JSON, which is the entire point of this script.
if [ -z "${only//[[:space:]]/}" ]; then
    printf '[]\n'
    exit 0
fi

# One tokenizer for all three spellings: drop the JSON punctuation, turn commas
# into spaces, and let the shell split what is left. The entries are plain names
# (x86_64, debian-bookworm-arm64, macos-14-arm64), so there is no JSON escaping
# to preserve and nothing subtler to parse.
cleaned="$(printf '%s' "$only" | tr -d '[]"'"'" | tr ',' ' ')"

selected=()
for entry in $cleaned; do
    known=false
    for v in "${valid[@]}"; do
        if [ "$entry" = "$v" ]; then
            known=true
            break
        fi
    done
    if [ "$known" = false ]; then
        echo "matrix-only.sh: '$entry' is not a matrix entry of this workflow." >&2
        echo "  Valid entries: ${valid[*]}" >&2
        echo "  Give them as [\"a\",\"b\"], a,b or a b - or leave it empty to build all of them." >&2
        exit 1
    fi
    # Ignore a repeat rather than emitting it twice.
    case " ${selected[*]-} " in
        *" $entry "*) ;;
        *) selected+=("$entry") ;;
    esac
done

# A value that was not empty but held no entries at all (say `,,`) means the
# same as empty: build everything. Saying so beats building nothing silently.
if [ "${#selected[@]}" -eq 0 ]; then
    printf '[]\n'
    exit 0
fi

out=""
for entry in "${selected[@]}"; do
    out="$out${out:+,}\"$entry\""
done
printf '[%s]\n' "$out"
