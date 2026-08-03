#!/bin/bash
#
# build-appimage.sh - turn a staged TSC into an AppImage, with its checksums.
#
# An AppImage is one file that runs on any Linux distribution without being
# installed, which is the thing a .deb cannot be: a .deb is built against one
# distribution's libraries and only installs there. That is also what decides
# how this is built - on an OLD distribution, with SFML compiled from source.
# glibc is backward compatible but not forward compatible, so an AppImage can
# only run on a system at least as new as the one it was built on; building it
# on Debian bookworm is what lets it run on everything from bookworm onwards,
# and SFML 3 has to come from source there because bookworm ships SFML 2.
#
# The libraries are bundled by linuxdeploy, which reads the ELF headers, copies
# every shared object the binary needs into the AppDir, and writes an AppRun
# that puts them on the search path.
#
# Environment:
#   TSC_VERSION   e.g. 2.2.0-beta2                        (required)
#   TSC_STAGE     the staging directory from build-tsc.sh (default: ./stage)
#   TSC_PREFIX    the prefix it was staged under          (default: /usr)
#   TSC_APPIMAGE_ARCH  x86_64 | aarch64 | armhf  (default: from uname -m)
#   TSC_OUT       where the AppImage is written           (default: ./dist)
#
# Produces, in $TSC_OUT, named the way the .deb assets are named - the game,
# the version, what it runs on - and with the same two checksum files beside it:
#   TSC-<version>-<arch>.AppImage
#   TSC-<version>-<arch>.md5sum
#   TSC-<version>-<arch>.sha256sum

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version="${TSC_VERSION:?TSC_VERSION is required}"
stage="${TSC_STAGE:-$repo_root/stage}"
prefix="${TSC_PREFIX:-/usr}"
out="${TSC_OUT:-$repo_root/dist}"

case "${TSC_APPIMAGE_ARCH:-$(uname -m)}" in
    x86_64|amd64)          arch=x86_64  ;;
    aarch64|arm64)         arch=aarch64 ;;
    armv7l|armhf|arm)      arch=armhf   ;;
    *)
        echo "build-appimage.sh: no AppImage runtime exists for" \
             "${TSC_APPIMAGE_ARCH:-$(uname -m)}." >&2
        echo "  AppImage supports x86_64, aarch64 and armhf only; the other" >&2
        echo "  architectures are covered by the .deb packages." >&2
        exit 1
        ;;
esac

if [ ! -d "$stage" ]; then
    echo "build-appimage.sh: no staged build at $stage - run build-tsc.sh first" >&2
    exit 1
fi

appdir="$repo_root/AppDir"
rm -rf "$appdir"
mkdir -p "$appdir"
cp -a "$stage"/. "$appdir"/

# linuxdeploy wants the prefix at the AppDir root. TSC is compiled for /usr, so
# usually it already is; move it if a different prefix was staged.
if [ "$prefix" != "/usr" ]; then
    mkdir -p "$appdir/usr"
    cp -a "$appdir$prefix"/. "$appdir/usr"/
    rm -rf "${appdir:?}$prefix"
fi

desktop="$appdir/usr/share/applications/org.secretchronicles.TSC.desktop"
icon="$appdir/usr/share/icons/hicolor/128x128/apps/org.secretchronicles.TSC.png"
for f in "$desktop" "$icon"; do
    if [ ! -f "$f" ]; then
        echo "build-appimage.sh: $f is missing from the staged build" >&2
        exit 1
    fi
done

tools="$repo_root/.appimage-tools"
mkdir -p "$tools"
if [ ! -x "$tools/linuxdeploy" ]; then
    wget -q -O "$tools/linuxdeploy" \
        "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${arch}.AppImage"
    chmod +x "$tools/linuxdeploy"
fi

# A container has no FUSE, so the tools cannot mount themselves; this makes
# them unpack into a temporary directory and run from there instead.
export APPIMAGE_EXTRACT_AND_RUN=1
export ARCH="$arch"
# Written into the AppImage's own metadata, and into the file name below.
export VERSION="$version"

mkdir -p "$out"
name="TSC-${version}-${arch}"

"$tools/linuxdeploy" \
    --appdir "$appdir" \
    --executable "$appdir/usr/bin/tsc" \
    --desktop-file "$desktop" \
    --icon-file "$icon" \
    --output appimage

# linuxdeploy names its output after the desktop file's Name and $VERSION; the
# release wants it named like every other asset.
produced="$(find . -maxdepth 1 -name '*.AppImage' -newer "$appdir" -print -quit)"
if [ -z "$produced" ]; then
    produced="$(find . -maxdepth 1 -name '*.AppImage' -print -quit)"
fi
if [ -z "$produced" ]; then
    echo "build-appimage.sh: linuxdeploy produced no AppImage" >&2
    exit 1
fi
mv "$produced" "$out/${name}.AppImage"
chmod +x "$out/${name}.AppImage"

(
    cd "$out"
    md5sum    "${name}.AppImage" > "${name}.md5sum"
    sha256sum "${name}.AppImage" > "${name}.sha256sum"
)

echo "Built $out/${name}.AppImage"
ls -l "$out/${name}.AppImage"
