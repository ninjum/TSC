#!/bin/bash
#
# build-deb.sh - turn a staged TSC into a .deb, with its checksum files.
#
# The v2.2.0-beta1 packages were built by hand, one directory per distribution
# and architecture, each holding a `tsc_2.2.0/DEBIAN/control` written out in
# full and a one-line `build-deb.sh` that ran `dpkg-deb --build tsc_2.2.0`. The
# layout here is the same; what is not the same is the Depends line.
#
# Writing Depends by hand is why beta1's packages carry a different one per
# distribution - libboost-chrono1.74.0 on bookworm, 1.83.0 on noble - and why
# the Installed-Size on all of them says 289459 whatever is actually inside.
# Both are now DERIVED: dpkg-shlibdeps reads the libraries the compiled binary
# actually links against and names the packages that provide them on THIS
# distribution, and du measures the staged tree. A distribution nobody has
# packaged for before therefore needs no new list, and a dependency that
# changes cannot be missed.
#
# Everything else about the package - the description, the section, the
# maintainer, the homepage - is the same text beta1 shipped.
#
# Environment:
#   TSC_VERSION   e.g. 2.2.0-beta2                     (required)
#   TSC_STAGE     the staging directory from build-tsc.sh (default: ./stage)
#   TSC_DISTRO    e.g. resolute, forky                 (required, names the file)
#   TSC_ARCH      Debian architecture, e.g. amd64      (default: dpkg's own)
#   TSC_OUT       where the .deb is written            (default: ./dist)
#
# TWO PACKAGES, because 99% of TSC is the same on every CPU. tsc/data is 289 MB
# of levels, worlds, music, graphics and scripting docs; tsc/src is 3.7 MB. Six
# architectures of one all-in-one package means shipping that 289 MB six times,
# and a repository carrying it six times over.
#
#   tsc       Architecture: <arch>   the binary and what is genuinely per-CPU
#   tsc-data  Architecture: all      the game's data, one package for every CPU
#
# This is what the project itself did at 2.1.0 - the alpha packages on the
# download page are tsc_<ver>_amd64.deb beside tsc-data_<ver>_all.deb - and it is
# what Debian expects of a game this shape. `tsc` depends on `tsc-data` of the
# same version, so installing the one you want pulls the other in.
#
# TSC_DATA_ONLY=1 builds only the data package. The workflow uses it to build
# that package ONCE rather than six identical times.
#
# Produces, in $TSC_OUT. The checksum files KEEP the full asset name and append
# .md5sum/.sha256sum - so every asset has its own pair, and two assets that share
# a stem (an AppImage and a Flatpak of one CPU, an .exe and a .7z) can never
# write to the same checksum file. The line inside still refers to the .deb, so
# `md5sum -c` works next to the package:
#   TSC-<version>-<distro>-<arch>.deb        (tsc, per CPU)
#   TSC-<version>-<distro>-<arch>.deb.md5sum
#   TSC-<version>-<distro>-<arch>.deb.sha256sum
#   TSC-<version>-data-all.deb               (tsc-data, every CPU)
#   TSC-<version>-data-all.deb.md5sum
#   TSC-<version>-data-all.deb.sha256sum

set -euo pipefail

# Name the line that failed.
#
# The resolute armhf build ended with "exit code 1" and not one line of output:
# build-tsc.sh printed "Staged TSC in /src/stage" and the job simply stopped. It
# was the `du` below - see the comment there - and it was invisible because its
# stderr goes to /dev/null while `set -e` still acted on its exit status. Any
# future silent failure says where it was instead.
trap 'rc=$?; echo "build-deb.sh: FAILED at line $LINENO: $BASH_COMMAND (exit $rc)" >&2; exit $rc' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version="${TSC_VERSION:?TSC_VERSION is required}"
distro="${TSC_DISTRO:?TSC_DISTRO is required}"
stage="${TSC_STAGE:-$repo_root/stage}"
arch="${TSC_ARCH:-$(dpkg --print-architecture)}"
out="${TSC_OUT:-$repo_root/dist}"
# The prefix TSC was staged under - the same default build-tsc.sh uses. The data
# lives at <prefix>/share/tsc, which is what the split below is drawn on.
prefix="${TSC_PREFIX:-/usr}"

# git refuses to touch a repository owned by somebody else - "detected dubious
# ownership in repository at '/src'" - and inside the build container that is
# every command, because the container runs as root while the checkout on the
# host belongs to the runner user. The check is for a shared machine where
# another user's repo might run hooks against you; here the "other user" is the
# same person one UID away, and the repository is the one this script was
# handed. Mark it safe.
git config --global --add safe.directory "$repo_root" 2>/dev/null || true
git config --global --add safe.directory '*' 2>/dev/null || true

if [ ! -d "$stage" ]; then
    echo "build-deb.sh: no staged build at $stage - run build-tsc.sh first" >&2
    exit 1
fi

# dpkg-deb wants the package tree named after the package, and the DEBIAN
# directory beside the files it installs. Build them next to the stage rather
# than in it, so the stage stays exactly what `make install` produced and can be
# packaged a second way (the AppImage) from the same bytes.
#
# The split is by path: everything under <prefix>/share/tsc is the game's data
# and is the same on every CPU; everything else - the binary, the man page, the
# desktop file, the icons - goes with the architecture. The icons and desktop
# file are arch-independent too, but they are kilobytes and they are what makes
# the package show up in a menu, so they stay with the part you install.
rm -rf "$repo_root/deb"

datadir_rel="${prefix#/}/share/tsc"
pkgdir="$repo_root/deb/tsc_${version}"
datadir="$repo_root/deb/tsc-data_${version}"

mkdir -p "$pkgdir" "$datadir"

if [ "${TSC_DATA_ONLY:-0}" != "1" ]; then
    cp -a "$stage"/. "$pkgdir"/
    rm -rf "${pkgdir:?}/${datadir_rel}"
    mkdir -p "$pkgdir/DEBIAN"
    cp "$repo_root/CHANGELOG" "$pkgdir/DEBIAN/CHANGELOG"
fi

mkdir -p "$datadir/$(dirname "$datadir_rel")" "$datadir/DEBIAN"
if [ -d "$stage/$datadir_rel" ]; then
    cp -a "$stage/$datadir_rel" "$datadir/$datadir_rel"
else
    echo "build-deb.sh: no $datadir_rel in the staged tree - the data package" >&2
    echo "  would be empty. Did build-tsc.sh install with this prefix?" >&2
    exit 1
fi
cp "$repo_root/CHANGELOG" "$datadir/DEBIAN/CHANGELOG"

mkdir -p "$out"

# ── The data package: Architecture: all, the same file on every CPU ──────────
# du can fail in a 32-bit userland: "cannot read directory ...: Value too large
# for defined data type" is EOVERFLOW, a 32-bit process meeting a 64-bit inode
# number on the host filesystem, and it happened building armhf under emulation.
# Installed-Size is informational - dpkg-deb builds a perfectly good package
# without it - so a package that cannot be measured is still worth shipping.
#
# `|| var=""` is what makes that true, and it was missing. 2>/dev/null hid du's
# MESSAGE but not its exit status: under `set -euo pipefail` the failing command
# substitution ended the script, so the resolute armhf build died here with exit
# 1 and no output at all, having just reported a successful staging. The forky
# armhf build beside it, on a different base image, measured fine - which is why
# it read as random rather than as this line.
data_installed_size="$(du -ks --exclude=DEBIAN "$datadir" 2>/dev/null | cut -f1)" || data_installed_size=""
{
    echo "Package: tsc-data"
    echo "Version: $version"
    echo "Architecture: all"
    echo "Maintainer: Lauri Ojansivu <x@xet7.org>"
    [ -n "$data_installed_size" ] && echo "Installed-Size: $data_installed_size"
    echo "Section: games"
    echo "Priority: optional"
    echo "Homepage: https://secretchronicles.org"
    echo "Description: Data files for TSC - Jump and Run game like Super Mario World"
    echo " The levels, worlds, music, sounds, graphics and scripting documentation"
    echo " for The Secret Chronicles of Dr. M. (TSC)."
    echo " ."
    echo " None of it depends on the CPU, so it is one package for every"
    echo " architecture rather than the same 280 MB repeated in each of them."
    echo " ."
    echo " Install the tsc package; this comes with it."
} > "$datadir/DEBIAN/control"

data_name="TSC-${version}-data-all"
dpkg-deb -Zxz --build "$datadir" "$out/${data_name}.deb"
(
    cd "$out"
    md5sum    "${data_name}.deb" > "${data_name}.deb.md5sum"
    sha256sum "${data_name}.deb" > "${data_name}.deb.sha256sum"
)
echo "Built $out/${data_name}.deb"
ls -l "$out/${data_name}.deb"

if [ "${TSC_DATA_ONLY:-0}" = "1" ]; then
    echo "TSC_DATA_ONLY=1: the architecture package was not built."
    exit 0
fi

# ── The architecture package: the binary and what goes with it ───────────────
installed_size="$(du -ks --exclude=DEBIAN "$pkgdir" 2>/dev/null | cut -f1)" || installed_size=""

# dpkg-shlibdeps needs a control file to exist before it will run, and it
# writes its answer into debian/substvars, so give it a minimal one first.
mkdir -p "$repo_root/deb/debian"
cat > "$repo_root/deb/debian/control" <<EOF
Source: tsc
Section: games
Priority: optional
Maintainer: Lauri Ojansivu <x@xet7.org>

Package: tsc
Architecture: $arch
Description: Jump and Run game like Super Mario World
EOF

depends=""
if command -v dpkg-shlibdeps >/dev/null 2>&1; then
    (
        cd "$repo_root/deb"
        # -O prints the field instead of writing substvars; the binary is the
        # only ELF object in the package.
        dpkg-shlibdeps -O --ignore-missing-info "tsc_${version}/${prefix#/}/bin/tsc" \
            2>/dev/null || true
    ) > "$repo_root/deb/shlibdeps.txt" || true
    depends="$(sed -n 's/^shlibs:Depends=//p' "$repo_root/deb/shlibdeps.txt" | head -n1)"
fi

if [ -z "$depends" ]; then
    echo "build-deb.sh: dpkg-shlibdeps produced nothing; the package will have" >&2
    echo "  no library Depends. It will still install, but apt will not pull the" >&2
    echo "  libraries in for you." >&2
fi

# The data package is a hard dependency, pinned to this exact version: a tsc
# binary with another version's levels is not a working game.
if [ -n "$depends" ]; then
    depends="tsc-data (= ${version}), ${depends}"
else
    depends="tsc-data (= ${version})"
fi

{
    echo "Package: tsc"
    echo "Version: $version"
    echo "Architecture: $arch"
    echo "Maintainer: Lauri Ojansivu <x@xet7.org>"
    echo "Original-Maintainer: Muammar El Khatib <muammar@debian.org>"
    [ -n "$installed_size" ] && echo "Installed-Size: $installed_size"
    echo "Depends: $depends"
    echo "Section: games"
    echo "Priority: optional"
    echo "Homepage: https://secretchronicles.org"
    echo "Description: Jump and Run game like Super Mario World"
    echo " The Secret Chronicles of Dr. M. (TSC) is an Open Source two-dimensional"
    echo " platform game with a style designed similar to classic sidescroller games."
    echo " ."
    echo " The game features a rich set of levels plus an advanced level editor that"
    echo " allows you to create your own levels. It is accompanied by a powerful"
    echo " scripting engine that utilises mruby, a minimal implementation of the Ruby"
    echo " programming language."
    echo " ."
    echo " TSC is a fork of the SMC project, whose development has stalled. Note however"
    echo " that our goals are different from those of the original SMC project, most"
    echo " notably we are working towards our own type of game rather than being solely"
    echo " inspired by one specific existing game."
    echo " ."
    echo " The game's data is in the tsc-data package, which this one depends on."
    echo " ."
    echo " Built for $distro on $arch from commit $(git -C "$repo_root" rev-parse --short HEAD)."
} > "$pkgdir/DEBIAN/control"

name="TSC-${version}-${distro}-${arch}"

# -Zxz because the default compressor changed between the distributions this
# builds on, and the file should be the same kind of thing everywhere.
dpkg-deb -Zxz --build "$pkgdir" "$out/${name}.deb"

(
    cd "$out"
    md5sum    "${name}.deb" > "${name}.deb.md5sum"
    sha256sum "${name}.deb" > "${name}.deb.sha256sum"
)

echo "Built $out/${name}.deb"
ls -l "$out/${name}.deb"
