#!/bin/bash
#
# build-tsc.sh - compile TSC for a RELEASE build and stage it for packaging.
#
# The same shape as ../../build-tsc.sh in the repository root, with the two
# differences a package needs:
#
#   * CMAKE_BUILD_TYPE=Release, not Debug. The root script builds Debug because
#     that is what you want when you are working on the game.
#   * the install goes to a STAGING DIRECTORY, not to the machine. The prefix
#     stays /usr - it is compiled into TSC as the place its data lives, so it
#     has to be the path the package will really be installed at - and DESTDIR
#     puts that tree somewhere else for dpkg-deb or appimagetool to pick up.
#     That is also why there is no sudo here: nothing is written outside the
#     build directory.
#
# Environment:
#   TSC_STAGE   where to install to (default: $PWD/stage)
#   TSC_PREFIX  the prefix TSC is compiled for (default: /usr)
#   TSC_JOBS    parallel compile jobs (default: nproc)
#
# Prints the staging directory on the last line.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
stage="${TSC_STAGE:-$repo_root/stage}"
prefix="${TSC_PREFIX:-/usr}"
jobs="${TSC_JOBS:-$(nproc)}"

# git refuses to touch a repository owned by somebody else - "detected dubious
# ownership in repository at '/src'" - and inside the build container that is
# every command, because the container runs as root while the checkout on the
# host belongs to the runner user. The check is for a shared machine where
# another user's repo might run hooks against you; here the "other user" is the
# same person one UID away, and the repository is the one this script was
# handed. Mark it safe.
git config --global --add safe.directory "$repo_root" 2>/dev/null || true
git config --global --add safe.directory '*' 2>/dev/null || true

cd "$repo_root"

# CEGUI, mruby and pod-parser are submodules and TSC compiles all three itself.
# --recursive because CEGUI has submodules of its own.
git submodule update --init --recursive

cd tsc

# The standalone tests, before anything is compiled: they need only a C++
# compiler and they take a couple of seconds, so every packaging job runs them
# and a broken one stops the release here rather than in a bug report about a
# published binary. That is how the 2.2.0-beta2 AppImage got out unable to find
# its own game data.
bash testing/run-tests.sh

# A build directory left over from a previous run would carry that run's cmake
# cache, including its CMAKE_BUILD_TYPE and prefix.
rm -rf build
mkdir build
cd build

cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      ..
make -j"$jobs"

rm -rf "$stage"
make install DESTDIR="$stage"

# The game is 240 MB of data and a stripped binary; symbols would double it for
# no use to anyone installing a release.
find "$stage$prefix/bin" -type f -exec strip --strip-unneeded {} + 2>/dev/null || true

echo "Staged TSC in $stage"
printf '%s\n' "$stage"
