#!/bin/bash
#
# download-checksums-test.sh - the download pages get the checksums they are
# missing, and nothing else changes.
#
# WHY THIS EXISTS. The website's download pages showed download links with an
# empty checksum cell:
#
#   * 2.2.0-beta2, the x86_64 and aarch64 AppImages and win64.exe. The release
#     HAS their .md5sum and .sha256sum - it has had them for a while. The page was
#     written by update-download-pages.py at a moment when it did not, and nothing
#     ever looked again.
#   * 2.1.0, bookworm-arm64.deb and bookworm-s390x.deb. Those rows are in the
#     hand-written stable table, which a beta rewrite never touches - and that
#     release published no checksum files at all.
#
# So the fix is not "rewrite the tables again": it is to walk the PAGES, find the
# holes, and fill each from the best evidence there is - the release's own
# checksum file, another checksum file whose CONTENT names the asset (2.1.0 drops
# the .deb from the name, so the content is what identifies it), or the file
# itself, downloaded and hashed.
#
# WHAT THIS CHECKS, offline. A fixture page with all four kinds of row and a
# stubbed `gh` standing in for the release: a cell filled from a published
# checksum, a cell filled by hashing the file, a legacy <stem>.sha256sum matched
# by its content, a row whose asset does not exist on the release (reported, left
# alone), and a row that already has a checksum (never touched). Then the
# workflow wiring: website.yml exists and only fills checksums, and both release
# workflows call it.
#
# Run: testing/download-checksums-test.sh

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/.."
script="$root/.github/scripts/fill-download-checksums.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
ok()   { echo "  ok   - $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL - $1"; failed=$((failed + 1)); }

echo "===== download pages: the missing checksums are filled in"

if [ -f "$script" ]; then
    ok "fill-download-checksums.py is present"
else
    fail "fill-download-checksums.py is missing"
    echo "===== download pages: $passed passed, $((failed + 1)) failed"
    exit 1
fi

# ── a release, as `gh` would describe it ─────────────────────────────────────
REPO="Secretchronicles/TSC"
rel="$work/release"
mkdir -p "$rel"

# The binary that has to be hashed, and one that is already checksummed.
printf 'pretend appimage payload\n' > "$rel/TSC-2.1.0-bookworm-amd64.deb"
EXPECT_SHA="$(sha256sum "$rel/TSC-2.1.0-bookworm-amd64.deb" | cut -d' ' -f1)"
EXPECT_MD5="$(md5sum "$rel/TSC-2.1.0-bookworm-amd64.deb" | cut -d' ' -f1)"
printf 'pretend appimage\n' > "$rel/TSC-2.2.0-beta2-x86_64.AppImage"
PUB_SHA="1b95963b18307bf57af1ec38083840f1882a399172db92f98e33da0b76fed102"
PUB_MD5="aaaabbbbccccddddeeeeffff00001111"
printf '%s  TSC-2.2.0-beta2-x86_64.AppImage\n' "$PUB_SHA" > "$rel/TSC-2.2.0-beta2-x86_64.AppImage.sha256sum"
printf '%s *TSC-2.2.0-beta2-x86_64.AppImage\n' "$PUB_MD5" > "$rel/TSC-2.2.0-beta2-x86_64.AppImage.md5sum"
# 2.1.0's legacy naming: the .deb is dropped from the checksum file's NAME, and
# only its CONTENT says which file it belongs to.
LEGACY_SHA="cccc1111dddd2222eeee3333ffff4444aaaa5555bbbb6666cccc7777dddd8888"
printf '%s  TSC-2.1.0-bullseye-arm64.deb\n' "$LEGACY_SHA" > "$rel/TSC-2.1.0-bullseye-arm64.sha256sum"
printf 'pretend deb\n' > "$rel/TSC-2.1.0-bullseye-arm64.deb"

# `gh` stand-in: view lists the release's assets, download copies them out.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/bin/bash
# gh release view <tag> --repo R --json assets --jq ...
# gh release download <tag> --repo R [--pattern P]... --dir D --clobber
# gh release upload <tag> FILE... --repo R --clobber
rel="$GH_FAKE_RELEASE"
case "$2" in
  view)
    tag="$3"
    [ -f "$rel/.tags/$tag" ] || exit 1
    while read -r n; do echo "$n"; done < "$rel/.tags/$tag"
    ;;
  download)
    tag="$3"; dir=""; pats=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --dir) dir="$2"; shift 2 ;;
        --pattern) pats+=("$2"); shift 2 ;;
        *) shift ;;
      esac
    done
    [ -f "$rel/.tags/$tag" ] || exit 1
    found=1
    while read -r n; do
      for p in "${pats[@]}"; do
        case "$n" in $p) [ -f "$rel/$n" ] && cp "$rel/$n" "$dir/$n" && found=0 ;; esac
      done
    done < "$rel/.tags/$tag"
    exit $found
    ;;
  upload)
    tag="$3"; shift 3
    for f in "$@"; do
      case "$f" in --*) continue ;; esac
      [ -f "$f" ] || continue
      cp "$f" "$rel/$(basename "$f")"
      echo "$(basename "$f")" >> "$rel/.tags/$tag"
      echo "uploaded $(basename "$f")"
    done
    ;;
esac
GH
chmod +x "$work/bin/gh"

mkdir -p "$rel/.tags"
cat > "$rel/.tags/v2.2.0-beta2" <<EOF
TSC-2.2.0-beta2-x86_64.AppImage
TSC-2.2.0-beta2-x86_64.AppImage.sha256sum
TSC-2.2.0-beta2-x86_64.AppImage.md5sum
EOF
cat > "$rel/.tags/v2.1.0" <<EOF
TSC-2.1.0-bookworm-amd64.deb
TSC-2.1.0-bullseye-arm64.deb
TSC-2.1.0-bullseye-arm64.sha256sum
EOF

# ── the page, with one row of each kind ──────────────────────────────────────
site="$work/website/en/download"
mkdir -p "$site"
base="https://github.com/Secretchronicles/TSC/releases/download"
cat > "$site/index.html" <<EOF
<html><body>
<table class="downloads">
  <tr><th>Version</th><th>Platform</th><th>CPU</th><th>File</th><th>Checksums</th></tr>
  <tr>
    <td>2.2.0-beta2</td><td>Any Linux</td><td>64-bit x86</td>
    <td><a href="$base/v2.2.0-beta2/TSC-2.2.0-beta2-x86_64.AppImage">TSC-2.2.0-beta2-x86_64.AppImage</a></td>
    <td>&nbsp;</td>
  </tr>
  <tr>
    <td>2.1.0</td><td>Debian 12</td><td>amd64</td>
    <td><a href="$base/v2.1.0/TSC-2.1.0-bookworm-amd64.deb">TSC-2.1.0-bookworm-amd64.deb</a></td>
    <td>&nbsp;</td>
  </tr>
  <tr>
    <td>2.1.0</td><td>Debian 11</td><td>arm64</td>
    <td><a href="$base/v2.1.0/TSC-2.1.0-bullseye-arm64.deb">TSC-2.1.0-bullseye-arm64.deb</a></td>
    <td>&nbsp;</td>
  </tr>
  <tr>
    <td>2.1.0</td><td>Debian 12</td><td>s390x</td>
    <td><a href="$base/v2.1.0/TSC-2.1.0-bookworm-s390x.deb">TSC-2.1.0-bookworm-s390x.deb</a></td>
    <td>&nbsp;</td>
  </tr>
  <tr>
    <td>2.1.0</td><td>Windows</td><td>64-bit x86</td>
    <td><a href="$base/v2.1.0/TSC-2.1.0-win64.exe">TSC-2.1.0-win64.exe</a></td>
    <td>MD5 sum:<br/><code>keepme</code></td>
  </tr>
</table>
</body></html>
EOF

out="$work/run.log"
GH_FAKE_RELEASE="$rel" GH_REPO="$REPO" PATH="$work/bin:$PATH" \
  python3 "$script" "$work/website" --upload > "$out" 2>&1
rc=$?
page="$(cat "$site/index.html")"

[ "$rc" = 0 ] && ok "it runs" || { fail "it exited $rc"; sed 's/^/      /' "$out"; }

case "$page" in
  *"$PUB_SHA"*) ok "a published checksum is used as it is (the beta2 AppImage case)" ;;
  *) fail "the published SHA256 did not reach the page" ;;
esac
case "$page" in
  *"$PUB_MD5"*) ok "and its MD5 beside it" ;;
  *) fail "the published MD5 did not reach the page" ;;
esac
case "$page" in
  *"$EXPECT_SHA"*) ok "a release with NO checksum file gets one computed from the file" ;;
  *) fail "the computed SHA256 did not reach the page" ;;
esac
case "$page" in
  *"$EXPECT_MD5"*) ok "and its MD5 too" ;;
  *) fail "the computed MD5 did not reach the page" ;;
esac
case "$page" in
  *"$LEGACY_SHA"*) ok "a legacy <stem>.sha256sum is matched by what is INSIDE it" ;;
  *) fail "the legacy-named checksum was not matched to its .deb" ;;
esac
case "$page" in
  *keepme*) ok "a row that already had a checksum is left exactly as it was" ;;
  *) fail "an existing checksum was overwritten" ;;
esac
# The row whose file is not on the release: reported, not invented, not deleted.
if grep -q "bookworm-s390x" "$out"; then
    ok "a link to a file the release does not have is reported"
else
    fail "the missing asset was not reported"
fi
case "$page" in
  *TSC-2.1.0-bookworm-s390x.deb*) ok "and its row is left alone rather than removed" ;;
  *) fail "the row for the missing asset disappeared" ;;
esac
# The computed digests are published, so the next run needs no download.
if [ -f "$rel/TSC-2.1.0-bookworm-amd64.deb.sha256sum" ]; then
    ok "--upload publishes the computed checksums back to the release"
else
    fail "--upload did not publish the computed checksums"
fi

# A second run must be a no-op: every cell is filled now.
before="$(md5sum "$site/index.html" | cut -d' ' -f1)"
GH_FAKE_RELEASE="$rel" GH_REPO="$REPO" PATH="$work/bin:$PATH" \
  python3 "$script" "$work/website" >/dev/null 2>&1
after="$(md5sum "$site/index.html" | cut -d' ' -f1)"
[ "$before" = "$after" ] && ok "running it again changes nothing" \
                         || fail "a second run rewrote the page"

# ── dry run changes nothing ──────────────────────────────────────────────────
cp "$site/index.html" "$work/keep.html"
printf '<tr><td>x</td><td><a href="%s/v2.1.0/TSC-2.1.0-bullseye-arm64.deb">f</a></td><td>&nbsp;</td></tr>\n' "$base" >> "$site/index.html"
sum_before="$(md5sum "$site/index.html" | cut -d' ' -f1)"
GH_FAKE_RELEASE="$rel" GH_REPO="$REPO" PATH="$work/bin:$PATH" \
  python3 "$script" "$work/website" --dry-run >/dev/null 2>&1
[ "$(md5sum "$site/index.html" | cut -d' ' -f1)" = "$sum_before" ] \
  && ok "--dry-run reports without writing" || fail "--dry-run wrote to the page"
cp "$work/keep.html" "$site/index.html"

# ── the workflows ────────────────────────────────────────────────────────────
wf="$root/.github/workflows/website.yml"
if [ -f "$wf" ]; then
    ok "website.yml exists"
else
    fail "website.yml is missing"
fi
if [ -f "$wf" ]; then
    grep -q "fill-download-checksums.py" "$wf" \
      && ok "and it runs the filler" || fail "website.yml does not run the filler"
    # ONLY checksums: it must not build packages or rebuild the repositories.
    if grep -qE "build-(deb|appimage|flatpak|tsc)\.sh|update-download-pages\.py|site/apt" "$wf"; then
        fail "website.yml does more than fill checksums"
    else
        ok "and does nothing else - no builds, no repository rebuild, no table rewrite"
    fi
    grep -q "workflow_call" "$wf" \
      && ok "it is callable by the release workflows" || fail "website.yml has no workflow_call"
fi
for f in release-all release-all-missing; do
    if grep -q "uses: ./.github/workflows/website.yml" "$root/.github/workflows/$f.yml"; then
        ok "$f.yml calls it, so a new build updates the pages"
    else
        fail "$f.yml does not call website.yml"
    fi
done
if grep -q "fill-download-checksums.py" "$root/.github/workflows/Repos.yml"; then
    ok "Repos.yml fills the holes its own rewrite leaves"
else
    fail "Repos.yml does not run the filler after update-download-pages.py"
fi

echo "===== download pages: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
