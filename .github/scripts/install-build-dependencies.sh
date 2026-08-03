#!/bin/bash
#
# install-build-dependencies.sh - the build dependencies, for a RELEASE build.
#
# The same job as ../../install-build-dependencies.sh in the repository root,
# which is the one to use on a development machine. This one differs in the
# three ways an automated build needs:
#
#   * no sudo. It runs as root inside the build container, and the container
#     images have no sudo installed.
#   * apt-get update first, and DEBIAN_FRONTEND=noninteractive, because a fresh
#     container has no package lists and nothing to answer a prompt with.
#   * --no-install-recommends, so the image stays small enough to be worth
#     caching and so nothing arrives that the build did not ask for.
#
# The package list itself is the CMake dependency list, kept next to the
# find_package() call that needs each one:
#
#   SFML 3          find_package(SFML ...)      - libsfml-dev, see below
#   OpenGL, GLEW    CEGUI's OpenGL renderer     - libgl1-mesa-dev, libglew-dev
#   GLM             CEGUI                       - libglm-dev
#   DevIL           CEGUI's image codec         - libdevil-dev
#   Expat           CEGUI's XML parser          - libexpat1-dev
#   FreeType        CEGUI                       - libfreetype-dev
#   PNG             find_package(PNG)           - libpng-dev
#   libxml++ 2.6    find_package(LibXmlPP 2.6)  - libxml++2.6-dev
#   Boost           filesystem, chrono, thread  - libboost-*-dev
#   X11             find_package(X11)           - libx11-dev
#   gettext         translations (ENABLE_NLS)   - gettext
#   Ruby + rake     building the bundled mruby  - ruby, ruby-dev, rake
#   bison, gperf    mruby and CEGUI             - bison, gperf
#   patch           ProvideCEGUI/ProvideMRuby apply the *.patch files in the
#                   repository root through ExternalProject's PATCH_COMMAND
#
# CEGUI and mruby are NOT in this list on purpose: TSC compiles both from its
# own submodules, statically (see tsc/cmake/modules/ProvideCEGUI.cmake).
#
# SFML: TSC needs 3.0.0 or newer since the SFML 3 port (#729). That is newer
# than most distributions ship - Debian has it from forky, Ubuntu from 26.04 -
# so the caller says which it wants:
#
#   TSC_SFML=distro  (default) install libsfml-dev from the distribution.
#                    Only correct where that package IS SFML 3; the check below
#                    stops the build early rather than letting cmake fail 20
#                    minutes in with a confusing message.
#   TSC_SFML=source  compile SFML from source and install it into /usr/local.
#                    This is what the AppImage build uses, because an AppImage
#                    bundles its libraries anyway and is built on an OLD
#                    distribution on purpose, to keep its glibc requirement low.
#
# Usage: install-build-dependencies.sh [extra apt packages...]

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

TSC_SFML="${TSC_SFML:-distro}"
SFML_VERSION="${SFML_VERSION:-3.0.2}"

apt-get update

packages=(
    build-essential
    ca-certificates
    cmake
    git
    patch
    pkg-config
    # mruby
    bison
    gperf
    rake
    ruby
    ruby-dev
    # translations
    gettext
    # TSC and CEGUI
    libboost-chrono-dev
    libboost-filesystem-dev
    libboost-thread-dev
    libdevil-dev
    libexpat1-dev
    libfreetype-dev
    libgl1-mesa-dev
    libglew-dev
    libglm-dev
    libglu1-mesa-dev
    libpng-dev
    libx11-dev
    libxml++2.6-dev
)

if [ "$TSC_SFML" = "distro" ]; then
    packages+=(libsfml-dev)
else
    # What SFML itself needs to compile. Its window and audio modules are the
    # only reason any of these is here.
    packages+=(
        libflac-dev
        libogg-dev
        libopenal-dev
        libudev-dev
        libvorbis-dev
        libxcursor-dev
        libxi-dev
        libxrandr-dev
        wget
    )
fi

apt-get install -y --no-install-recommends "${packages[@]}" "$@"

if [ "$TSC_SFML" = "distro" ]; then
    # Fail here, with the version in the message, rather than inside cmake.
    sfml_version="$(dpkg-query --showformat='${Version}' --show libsfml-dev)"
    case "$sfml_version" in
        3.*)
            echo "SFML $sfml_version from the distribution - ok"
            ;;
        *)
            echo "install-build-dependencies.sh: this distribution ships SFML" >&2
            echo "  $sfml_version, and TSC needs 3.0.0 or newer since the SFML 3" >&2
            echo "  port. Build on a newer distribution, or set TSC_SFML=source." >&2
            exit 1
            ;;
    esac
else
    echo "Compiling SFML $SFML_VERSION from source into /usr/local"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    wget -q -O "$tmp/sfml.tar.gz" \
        "https://github.com/SFML/SFML/archive/refs/tags/${SFML_VERSION}.tar.gz"
    tar xzf "$tmp/sfml.tar.gz" -C "$tmp"
    cmake -S "$tmp/SFML-${SFML_VERSION}" -B "$tmp/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=ON \
        -DSFML_BUILD_EXAMPLES=OFF \
        -DSFML_BUILD_DOC=OFF
    cmake --build "$tmp/build" -j "$(nproc)"
    cmake --install "$tmp/build"
    ldconfig
fi
