#!/bin/bash
#
# expected-assets.sh <version> - every asset a complete TSC release carries.
#
# Prints one line per PRIMARY asset:
#
#   <kind> <selector> <asset-name> <sums|nosums>
#
# `kind` is the workflow that builds it (deb, appimage, flatpak, windows, mac);
# `selector` is the value that workflow's `only` input filters its matrix on, so
# release-all-missing.yml can say "build these three and nothing else".
#
# The CHECKSUMS are not listed, they are DERIVED. Every one of these workflows
# writes `<name>.md5sum` and `<name>.sha256sum` beside the file with the
# extension DROPPED - TSC-2.2.0-beta2-x86_64.AppImage is checksummed as
# TSC-2.2.0-beta2-x86_64.md5sum - so `sums` means "and those two as well". Such
# an asset counts as present only when all three are there: a package whose
# checksum upload failed is a half-published release, and treating the package
# alone as present would leave it that way.
#
# `nosums` is for the build-script zips, which are published without checksums.
# Requiring them would leave those two permanently "missing".
#
# THE LISTS BELOW MUST MATCH THE WORKFLOWS' MATRICES. Each is named beside it.
# If a distro or an architecture is added there and not here, this will not
# notice it is missing - which is the one way this script can be wrong without
# anything failing.
#
# Verified against the real v2.2.0-beta2 release: the 44 assets it carries are
# exactly the ones this prints, minus the .deb for resolute armhf, the armhf
# AppImage, both Flatpaks, both Windows installers and every macOS image - which
# are precisely the jobs that failed in that run.

set -euo pipefail

v="${1:?usage: expected-assets.sh <version>   e.g. 2.2.0-beta2}"

# Deb.yml: two distributions times six architectures, plus the one
# architecture-independent data package built once for all of them.
for distro in resolute forky; do
    for arch in amd64 arm64 armhf ppc64el riscv64 s390x; do
        echo "deb ${distro}-${arch} TSC-${v}-${distro}-${arch}.deb sums"
    done
done
echo "deb data TSC-${v}-data-all.deb sums"

# The build scripts beta1 published, one zip per distribution: the record of how
# that distribution's packages were made. They are assembled by Deb.yml's attach
# job out of every architecture's artifacts, not by one matrix entry, so they
# have no architecture of their own - which is why a MISSING one asks for the
# whole Deb workflow rather than a filtered run (see release-all-missing.yml).
# Their names carry no version, so they are the one pair here that does not
# start with TSC-${v}.
for distro in resolute forky; do
    echo "deb scripts-${distro} ${distro}-build-deb.zip nosums"
done

# AppImage.yml
for arch in x86_64 aarch64 armhf; do
    echo "appimage ${arch} TSC-${v}-${arch}.AppImage sums"
done

# Flatpak.yml
for arch in x86_64 aarch64; do
    echo "flatpak ${arch} TSC-${v}-${arch}.flatpak sums"
done

# Windows.yml: the two builds, and the combined installer that carries both and
# is only made when both exist.
for name in win64 win32; do
    echo "windows ${name} TSC-${v}-${name}.exe sums"
done
echo "windows combined TSC-${v}-windows.exe sums"

# Mac.yml: macOS 15 and 26 on arm64, macOS 15 on Intel, and the universal image
# lipo welds from the two arm64/x86_64 builds.
echo "mac 15-arm64 TSC-${v}-macos15-arm64.dmg sums"
echo "mac 26-arm64 TSC-${v}-macos26-arm64.dmg sums"
echo "mac 15-x86_64 TSC-${v}-macos15-x86_64.dmg sums"
echo "mac universal TSC-${v}-macos-universal.dmg sums"
