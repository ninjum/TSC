#!/bin/bash
#
# cegui-greyscale-test.sh - the shipped image codec can read every PNG in the
# game data, including the greyscale ones.
#
# WHY THIS EXISTS. The AppImage started, played, took keyboard and mouse - and
# printed 26 of these on the way:
#
#   CEGUI::RendererException ... STBImageCodec - stb_image.c based image codec
#   failed to load image 'blocks/brick/1_grey.png'.
#   Warning: Failed to load as editor item image: ".../blocks/brick/1_grey.png"
#   Using dummy image instead.
#
# Not a bit-depth problem this time - png-bit-depth-test.sh passed 1029 of 1029
# while every one of these was broken, which is the reason this second test
# exists. Every failing file was 8-bit and non-interlaced. What they had in
# common was their COLOUR TYPE: 0 (greyscale) or 4 (greyscale+alpha).
#
# CEGUI's STBImageCodec, in cegui/src/ImageCodecModules/STB/ImageCodec.cpp:
#
#     unsigned char* image = stbi_load_from_memory(..., &comp, 0);
#     switch (comp) {
#     case 4: format = Texture::PF_RGBA; break;
#     case 3: format = Texture::PF_RGB;  break;
#     default:
#         ... "Invalid image format. Only RGB and RGBA images are supported"
#
# The 0 means "give me whatever channel count the file has". Greyscale is ONE
# channel and greyscale+alpha is TWO, so stb decoded them perfectly well and the
# switch threw them away.
#
# The fix is cegui-stb-greyscale.patch, applied by ProvideCEGUI.cmake's
# PATCH_COMMAND: when comp is 1 or 2 it reloads asking stb for RGBA, which is
# the same decoder doing the widening the caller would otherwise do - stb's own
# convert_format has CASE(1,4), filling an opaque alpha, and CASE(2,4), keeping
# the image's own. 3- and 4-channel images are not touched at all.
#
# CONVERTING THE 38 FILES WOULD ALSO HAVE WORKED, and would have been wrong:
# it fixes these 38 and nothing else, so a greyscale PNG in somebody's own level
# or campaign still draws a dummy image. Fixing the codec fixes every greyscale
# PNG the game will ever open.
#
# Run: testing/cegui-greyscale-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/.."
patchfile="$root/cegui-stb-greyscale.patch"
provide="$root/tsc/cmake/modules/ProvideCEGUI.cmake"
data="$root/tsc/data"
codec_rel="cegui/src/ImageCodecModules/STB/ImageCodec.cpp"

passed=0
failed=0
ok()   { echo "  ok   - $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL - $1"; failed=$((failed + 1)); }

echo "===== CEGUI image codec: greyscale PNGs are readable"

# ------------------------------------------------------------- the patch exists

if [ -f "$patchfile" ]; then
    ok "cegui-stb-greyscale.patch is present"
else
    fail "cegui-stb-greyscale.patch is missing; greyscale PNGs draw dummy images"
    echo "===== CEGUI image codec: $passed passed, $((failed + 1)) failed"
    exit 1
fi

# It must patch the codec, and it must be a real unified diff - a patch that
# applies to nothing still "exists".
if grep -q -- "^--- a/$codec_rel" "$patchfile" && grep -q -- "^+++ b/$codec_rel" "$patchfile"; then
    ok "it patches the STB image codec"
else
    fail "the patch does not name $codec_rel"
fi

if grep -q '^@@' "$patchfile"; then
    ok "and it is a unified diff with a hunk"
else
    fail "no @@ hunk header; patch(1) would reject it"
fi

# The substance: the 1- and 2-channel cases are reloaded as RGBA.
if grep -q 'comp == 1 || comp == 2' "$patchfile"; then
    ok "it handles BOTH greyscale and greyscale+alpha"
else
    fail "the patch does not reload the 1- and 2-channel cases"
fi

if grep -qE '^\+.*stbi_load_from_memory' "$patchfile" && grep -qE '^\+.*, 4\);' "$patchfile"; then
    ok "by asking stb for 4 channels"
else
    fail "nothing in the patch requests RGBA from stb"
fi

# NEGATIVE: it must not widen 3- and 4-channel images too. Those are 962 of the
# 1029 files; turning every RGB texture into RGBA would cost VRAM for nothing,
# and would be a silent change to images that were never broken.
if grep -qE '^\+.*(comp == 3|comp = 4;$)' "$patchfile" \
   && grep -qE '^-.*&comp, 0\);' "$patchfile"; then
    fail "the patch changes the default load; 3- and 4-channel images must be untouched"
else
    ok "negative: images that already worked are loaded exactly as before"
fi

# ------------------------------------------------------- the patch is applied

if grep -q 'cegui-stb-greyscale.patch' "$provide"; then
    ok "ProvideCEGUI.cmake applies it"
else
    fail "the patch exists but nothing applies it - PATCH_COMMAND does not name it"
fi

# In the PATCH_COMMAND specifically, not merely mentioned in a comment.
if grep -E '^\s*PATCH_COMMAND' "$provide" | grep -q 'cegui-stb-greyscale.patch'; then
    ok "and it is in PATCH_COMMAND, not just described in a comment"
else
    fail "cegui-stb-greyscale.patch is named but not in PATCH_COMMAND"
fi

# The other two patches must still be applied; a && chain is easy to break.
for p in cegui-cpp11.patch cegui-cmake-policy.patch; do
    if grep -E '^\s*PATCH_COMMAND' "$provide" | grep -q "$p"; then
        ok "$p is still applied"
    else
        fail "$p was dropped from PATCH_COMMAND"
    fi
done

# --------------------------------------------- it still applies to the source

# Only when the submodule is checked out. A fresh clone has an empty cegui/, and
# that is not a failure - but when the source IS there, a submodule bump that
# moves this code must be caught here rather than during a release build.
if [ -f "$root/cegui/$codec_rel" ]; then
    if (cd "$root/cegui" && patch -p1 --dry-run --silent < "$patchfile") >/dev/null 2>&1; then
        ok "it still applies cleanly to the pinned CEGUI source"
    else
        fail "the patch no longer applies to cegui/$codec_rel - the submodule moved"
    fi
else
    echo "  --   cegui/ submodule is not checked out; skipping the apply check"
fi

# ------------------------------------- the data this is all about, if present

if [ -d "$data" ]; then
    grey=0
    total=0
    while IFS= read -r png; do
        total=$((total + 1))
        # IHDR is fixed-layout: 8-byte signature, 4-byte length, "IHDR", then
        # width and height as 4 bytes each - so colour type is the byte at 25.
        c="$(od -An -tu1 -j 25 -N 1 "$png" 2>/dev/null | tr -d ' \n')"
        case "$c" in 0|4) grey=$((grey + 1)) ;; esac
    done < <(find "$data" -name '*.png' -type f)

    if [ "$total" -eq 0 ]; then
        fail "no PNGs found under $data; this half checked nothing"
    else
        echo "  --   $total PNGs in the game data, $grey of them greyscale"
        if [ "$grey" -gt 0 ]; then
            # This is the link between the two halves: greyscale files exist, so
            # the patch is not optional. If somebody converts them all away one
            # day this still passes - and the patch stays, for everyone else's.
            ok "greyscale PNGs are present, so the codec patch is load-bearing"
        else
            ok "no greyscale PNGs today; the patch still covers user content"
        fi
    fi
else
    echo "  --   no game data at $data; skipping the data check"
fi

echo "===== CEGUI image codec: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
