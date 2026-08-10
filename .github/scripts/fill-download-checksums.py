#!/usr/bin/env python3
#
# fill-download-checksums.py <website-root> [--upload] [--limit-mb N] [--dry-run]
#
# Fill in the EMPTY checksum cells of the website's download pages
# (en/es/fi/download/index.html), for every release they offer, and leave
# everything else alone.
#
# WHY THIS EXISTS, and why it is separate from update-download-pages.py. That
# script rewrites one release's tables from scratch, with whatever checksums the
# release publishes AT THAT MOMENT. Two things leave holes behind:
#
#   * A checksum that arrives LATER. The 2.2.0-beta2 page was generated while the
#     AppImage and Windows jobs had uploaded their binaries but not yet their
#     .md5sum/.sha256sum files, so those rows were written with an empty cell -
#     and nothing ever looked at them again. The files are on the release today;
#     the page still says nothing.
#   * A table this repo does not generate. The stable 2.1.0 tables are
#     hand-written, outside the TSC-DOWNLOADS markers, so a rewrite for the beta
#     never touches them - and that release published no checksum files at all.
#
# So this walks the pages themselves rather than a release: every row that links
# a release asset and shows no checksum is a hole, and each hole is filled from
# the best evidence available, in this order:
#
#   1. the release's own <asset>.sha256sum / <asset>.md5sum, if published;
#   2. any other checksum file on that release whose CONTENT names the asset -
#      2.1.0 names them <stem>.sha256sum, dropping the .deb, and the content is
#      what makes that unambiguous;
#   3. the file itself: download it, compute both digests, and with --upload
#      publish them as .md5sum/.sha256sum assets so nobody has to download it
#      again.
#
# A row whose asset DOES NOT EXIST on the release is reported and left alone -
# that is a page advertising a file that was never built (2.1.0's
# bookworm-arm64.deb and bookworm-s390x.deb), and inventing a checksum for it, or
# quietly deleting the row, are both worse than saying so.
#
# The tag comes from the download URL in the row, so one run covers every release
# the pages offer without being told which.
#
# gh talks to $GH_REPO (default Secretchronicles/TSC) and needs GH_TOKEN, as in
# Actions. --upload additionally needs write access to that repository.

import os, re, sys, html, hashlib, subprocess, tempfile

REPO = os.environ.get("GH_REPO", "Secretchronicles/TSC")
LANGS = ("en", "es", "fi")
# Only follow links that point at a release of this repository.
URL_RE = re.compile(
    r"https://github\.com/([^/\s\"]+/[^/\s\"]+)/releases/download/([^/\s\"]+)/([^\"\s<>]+)")
# A checksum cell counts as EMPTY when it holds nothing, whitespace, or &nbsp;
# (which is what update-download-pages.py writes when it has no digest).
EMPTY_CELL_RE = re.compile(r"^(?:\s|&nbsp;|&#160;)*$")
ROW_RE = re.compile(r"<tr>(.*?)</tr>", re.S)
CELL_RE = re.compile(r"<td[^>]*>(.*?)</td>", re.S)


def sh(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def release_assets(tag):
    """Asset names on one release, or None when there is no such release."""
    r = sh(["gh", "release", "view", tag, "--repo", REPO, "--json", "assets",
            "--jq", ".assets[].name"])
    if r.returncode != 0:
        return None
    return [n for n in r.stdout.split("\n") if n.strip()]


def fetch_sums(tag, into):
    """Every checksum file on the release, keyed by the name INSIDE it.

    The name in the file is what identifies the binary: 2.1.0's checksum assets
    are called <stem>.sha256sum with the .deb dropped, so the file name alone
    cannot be trusted, and the content can.
    """
    sh(["gh", "release", "download", tag, "--repo", REPO,
        "--pattern", "*.md5sum", "--pattern", "*.sha256sum",
        "--dir", into, "--clobber"])
    md5, sha = {}, {}
    for fn in sorted(os.listdir(into)):
        try:
            line = open(os.path.join(into, fn), encoding="utf-8").read().strip().split("\n")[0]
        except OSError:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        # md5sum/sha256sum write " *name" in binary mode, and some tools write a
        # path; the basename is the asset.
        target = os.path.basename(parts[-1].lstrip("*"))
        (md5 if fn.endswith(".md5sum") else sha)[target] = parts[0]
    return md5, sha


def compute(tag, asset, workdir, limit_mb):
    """Download one asset and return (md5, sha256), or (None, None)."""
    r = sh(["gh", "release", "download", tag, "--repo", REPO,
            "--pattern", asset, "--dir", workdir, "--clobber"])
    path = os.path.join(workdir, asset)
    if r.returncode != 0 or not os.path.exists(path):
        return None, None
    size_mb = os.path.getsize(path) / (1024 * 1024)
    if limit_mb and size_mb > limit_mb:
        print("    too big to hash here (%.0f MB > %d MB limit); skipped" % (size_mb, limit_mb))
        os.remove(path)
        return None, None
    m, s = hashlib.md5(), hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            m.update(chunk)
            s.update(chunk)
    os.remove(path)
    return m.hexdigest(), s.hexdigest()


def upload_sums(tag, asset, md5, sha, workdir):
    """Publish the computed digests as the release's own checksum files."""
    ok = True
    for suffix, digest in ((".md5sum", md5), (".sha256sum", sha)):
        if not digest:
            continue
        p = os.path.join(workdir, asset + suffix)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("%s  %s\n" % (digest, asset))
        r = sh(["gh", "release", "upload", tag, p, "--repo", REPO, "--clobber"])
        if r.returncode != 0:
            print("    upload of %s failed: %s" % (os.path.basename(p), r.stderr.strip()[:200]))
            ok = False
        os.remove(p)
    return ok


def cell_html(md5, sha):
    """The same shape update-download-pages.py writes, so the two agree."""
    bits = []
    if md5:
        bits.append("MD5 sum:<br/><code>%s</code>" % md5)
    if sha:
        bits.append("SHA256 sum:<br/><code>%s</code>" % sha)
    return "<br/>".join(bits) if bits else "&nbsp;"


def main():
    args = [a for a in sys.argv[1:]]
    upload = "--upload" in args
    dry = "--dry-run" in args
    limit_mb = 0
    if "--limit-mb" in args:
        limit_mb = int(args[args.index("--limit-mb") + 1])
    positional = [a for a in args if not a.startswith("--") and not a.isdigit()]
    if not positional:
        sys.exit("usage: fill-download-checksums.py <website-root> [--upload] "
                 "[--limit-mb N] [--dry-run]")
    root = positional[0]

    sums_cache, assets_cache = {}, {}
    filled = computed = missing_asset = 0
    unresolved = []

    with tempfile.TemporaryDirectory() as tmp:
        for lang in LANGS:
            path = os.path.join(root, lang, "download", "index.html")
            if not os.path.exists(path):
                print("%s: no download page, skipped" % lang)
                continue
            text = open(path, encoding="utf-8").read()
            out, last, changed = [], 0, 0

            for row in ROW_RE.finditer(text):
                cells = list(CELL_RE.finditer(row.group(1)))
                if len(cells) < 2:
                    continue
                link = URL_RE.search(row.group(1))
                if not link:
                    continue
                checksum_cell = cells[-1]
                if not EMPTY_CELL_RE.match(checksum_cell.group(1)):
                    continue  # already has one; never overwrite

                repo_of_link, tag, asset = link.group(1), link.group(2), html.unescape(link.group(3))
                if repo_of_link != REPO:
                    continue

                if tag not in assets_cache:
                    assets_cache[tag] = release_assets(tag)
                names = assets_cache[tag]
                if names is None:
                    print("  %s: no such release; %s left alone" % (tag, asset))
                    continue
                if asset not in names:
                    missing_asset += 1
                    unresolved.append("%s/%s (the page links a file this release does not have)"
                                      % (tag, asset))
                    continue

                if tag not in sums_cache:
                    d = os.path.join(tmp, tag.replace("/", "_"))
                    os.makedirs(d, exist_ok=True)
                    sums_cache[tag] = fetch_sums(tag, d)
                md5map, shamap = sums_cache[tag]
                md5, sha = md5map.get(asset), shamap.get(asset)

                if not (md5 and sha):
                    print("  %s/%s: no published checksum; computing from the file" % (tag, asset))
                    if dry:
                        continue
                    cmd5, csha = compute(tag, asset, tmp, limit_mb)
                    md5, sha = md5 or cmd5, sha or csha
                    if md5 or sha:
                        computed += 1
                        md5map[asset], shamap[asset] = md5, sha
                        if upload:
                            upload_sums(tag, asset, cmd5, csha, tmp)

                if not (md5 or sha):
                    unresolved.append("%s/%s (could not be checksummed)" % (tag, asset))
                    continue

                # Splice the new cell in, keeping everything else byte for byte.
                start = row.start(1) + checksum_cell.start(1)
                end = row.start(1) + checksum_cell.end(1)
                out.append(text[last:start])
                out.append(cell_html(md5, sha))
                last = end
                changed += 1
                filled += 1

            if changed and not dry:
                out.append(text[last:])
                open(path, "w", encoding="utf-8").write("".join(out))
            print("%s: %d checksum cell(s) filled" % (lang, changed))

    print("\nfilled %d cell(s); %d checksum(s) computed from the file itself" % (filled, computed))
    if unresolved:
        print("left alone (%d):" % len(unresolved))
        for u in sorted(set(unresolved)):
            print("  - %s" % u)
    # A page that advertises a file the release does not have is worth a warning
    # in the log, but it is not this script's business to fail a release for it.
    if missing_asset:
        print("::warning::%d download link(s) point at files that are not on their release; "
              "either build them or remove the rows." % missing_asset)
    return 0


if __name__ == "__main__":
    sys.exit(main())
