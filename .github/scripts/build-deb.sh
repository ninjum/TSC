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
# Produces, in $TSC_OUT, named exactly as the v2.2.0-beta1 release named them -
# the checksum files drop the .deb from their own name but still refer to the
# .deb inside, which is what makes `md5sum -c` work next to the package:
#   TSC-<version>-<distro>-<arch>.deb
#   TSC-<version>-<distro>-<arch>.md5sum
#   TSC-<version>-<distro>-<arch>.sha256sum

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version="${TSC_VERSION:?TSC_VERSION is required}"
distro="${TSC_DISTRO:?TSC_DISTRO is required}"
stage="${TSC_STAGE:-$repo_root/stage}"
arch="${TSC_ARCH:-$(dpkg --print-architecture)}"
out="${TSC_OUT:-$repo_root/dist}"

if [ ! -d "$stage" ]; then
    echo "build-deb.sh: no staged build at $stage - run build-tsc.sh first" >&2
    exit 1
fi

# dpkg-deb wants the package tree named after the package, and the DEBIAN
# directory beside the files it installs. Build it next to the stage rather
# than in it, so the stage stays exactly what `make install` produced and can
# be packaged a second way (the AppImage) from the same bytes.
pkgdir="$repo_root/deb/tsc_${version}"
rm -rf "$repo_root/deb"
mkdir -p "$pkgdir"
cp -a "$stage"/. "$pkgdir"/
mkdir -p "$pkgdir/DEBIAN"

# The changelog IS the repository's CHANGELOG - the same file the version was
# read from, and the same thing beta1's packages carried.
cp "$repo_root/CHANGELOG" "$pkgdir/DEBIAN/CHANGELOG"

installed_size="$(du -ks --exclude=DEBIAN "$pkgdir" | cut -f1)"

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
        dpkg-shlibdeps -O --ignore-missing-info "tsc_${version}/usr/bin/tsc" \
            2>/dev/null || true
    ) > "$repo_root/deb/shlibdeps.txt" || true
    depends="$(sed -n 's/^shlibs:Depends=//p' "$repo_root/deb/shlibdeps.txt" | head -n1)"
fi

if [ -z "$depends" ]; then
    echo "build-deb.sh: dpkg-shlibdeps produced nothing; the package will have" >&2
    echo "  no Depends line. It will still install, but apt will not pull the" >&2
    echo "  libraries in for you." >&2
fi

{
    echo "Package: tsc"
    echo "Version: $version"
    echo "Architecture: $arch"
    echo "Maintainer: Lauri Ojansivu <x@xet7.org>"
    echo "Original-Maintainer: Muammar El Khatib <muammar@debian.org>"
    echo "Installed-Size: $installed_size"
    [ -n "$depends" ] && echo "Depends: $depends"
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
    echo " Built for $distro on $arch from commit $(git -C "$repo_root" rev-parse --short HEAD)."
} > "$pkgdir/DEBIAN/control"

mkdir -p "$out"
name="TSC-${version}-${distro}-${arch}"

# -Zxz because the default compressor changed between the distributions this
# builds on, and the file should be the same kind of thing everywhere.
dpkg-deb -Zxz --build "$pkgdir" "$out/${name}.deb"

(
    cd "$out"
    md5sum    "${name}.deb" > "${name}.md5sum"
    sha256sum "${name}.deb" > "${name}.sha256sum"
)

echo "Built $out/${name}.deb"
ls -l "$out/${name}.deb"
