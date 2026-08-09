#!/bin/bash
#
# png-bit-depth-test.sh - every PNG in the game data must be at least 8 bits per
# channel, because the image codec TSC ships cannot decode less.
#
# WHY THIS EXISTS. The 2.2.0-beta2 AppImage started, drew its loading bar, and
# then aborted:
#
#   CEGUI::RendererException ... STBImageCodec - stb_image.c based image codec
#   failed to load image 'darkening.png'.
#
# darkening.png was a 1-BIT COLORMAP PNG. It had always been one, and it had
# always worked - under DevIL. When CEGUI was switched to its built-in STB image
# codec (so the macOS and Windows builds would link), that switch quietly took
# away support for sub-8-bit PNG depths: CEGUI 0.8 vendors an old stb_image.c
# that handles 8 and 16 bits only. Five files out of 1024 were affected, and the
# first one the GUI touched killed the process.
#
# Nothing catches this at build time. The data is copied, not decoded, so the
# build succeeds; `tsc --print-paths` confirms the data is FINDABLE, which was
# the previous bug, and says nothing about whether it DECODES. It only shows up
# when a particular image is loaded at runtime, on a machine with a display. So
# it is checked here, over the files themselves, in the run that already exists.
#
# HOW. A PNG's IHDR is fixed-layout: the 8-byte signature, a 4-byte length, the
# type "IHDR", then width and height as 4 bytes each - so BIT DEPTH is the single
# byte at offset 24 and COLOUR TYPE the byte at 25. That is read directly with
# od, so this needs no image library, no `file`, and no Python: just the shell
# the rest of the test run already uses.
#
# Run: testing/png-bit-depth-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data="$here/../tsc/data"

if [ ! -d "$data" ]; then
    echo "png-bit-depth-test.sh: no game data at $data" >&2
    exit 1
fi

# The lowest bit depth the shipped codec can read.
MIN_DEPTH=8

passed=0
failed=0
checked=0

# byte_at FILE OFFSET - one unsigned byte, or "" when it cannot be read.
byte_at() {
    od -An -tu1 -j "$2" -N 1 "$1" 2>/dev/null | tr -d ' \n'
}

echo "===== PNG bit depth: every image must be >= ${MIN_DEPTH} bits"

while IFS= read -r png; do
    checked=$((checked + 1))

    depth="$(byte_at "$png" 24)"
    colour="$(byte_at "$png" 25)"

    # A PNG whose IHDR cannot be read is not a PNG the game can load either.
    if [ -z "$depth" ]; then
        echo "  FAIL - $png: could not read its IHDR"
        failed=$((failed + 1))
        continue
    fi

    if [ "$depth" -lt "$MIN_DEPTH" ]; then
        echo "  FAIL - ${png#$data/}: ${depth}-bit (colour type $colour)"
        echo "          The shipped STB image codec decodes 8 and 16 bits only."
        echo "          Convert it, losslessly:"
        echo "            magick '${png#$data/}' -define png:color-type=6 -define png:bit-depth=8 '${png#$data/}'"
        failed=$((failed + 1))
        continue
    fi

    passed=$((passed + 1))
done < <(find "$data" -name '*.png' -type f | sort)

echo "===== $checked PNGs checked, $passed at or above ${MIN_DEPTH} bits, $failed too low"

if [ "$checked" -eq 0 ]; then
    # A test that checks nothing must not report success: an empty data tree
    # means the check was not run, not that everything passed.
    echo "  FAIL - no PNGs found; this test checked nothing" >&2
    exit 1
fi

[ "$failed" -eq 0 ]
