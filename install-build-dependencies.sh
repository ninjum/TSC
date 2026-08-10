#!/bin/bash

# Requires Debian 9 or Ubuntu 16.10 or newer

# Install deb packages
# No libpcre3-dev: CEGUI's editbox validation is built with std::regex here
# (cegui-std-regex.patch, and -DCEGUI_HAS_PCRE_REGEX=OFF in ProvideCEGUI.cmake),
# so PCRE 1 - which is end-of-life, gone from MSYS2's mingw repositories and
# deprecated in Homebrew - is not needed on any platform any more.
sudo apt-get -y install ruby-full rake gperf pkg-config bison libglew-dev \
  freeglut3-dev gettext libpng-dev libxml++2.6-dev \
  libfreetype6-dev libdevil-dev libboost-all-dev libsfml-dev \
  cmake build-essential git git-core libglm-dev

# Quintus added newer CEGUI 2024-10-04, so this is not installed anymore:
#  libcegui-mk2-dev


# Install Ruby gems
sudo gem install bundler nanoc adsf kramdown coderay
