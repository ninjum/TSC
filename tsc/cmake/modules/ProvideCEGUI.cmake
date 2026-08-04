#############################################################################
# ProvideCEGUI.cmake - Compiles CEGUI from source
#
# Copyright © 2012-2024 The TSC Contributors
#############################################################################

# This is required for TSC's config.hpp
set(CEGUI_USE_EXPAT 1)

# CEGUI dependencies
find_package(DevIL REQUIRED)
find_package(Freetype REQUIRED)
find_package(EXPAT REQUIRED)
find_package(GLEW REQUIRED)

# Which name GLEW answers to depends on HOW it was found, and that differs by
# platform. GLEW 2.3 ships a CMake CONFIG package; 2.2 does not.
#
#   Ubuntu 26.04, GLEW 2.2.0   no config package, so CMake's own FindGLEW
#                              module runs and sets GLEW_LIBRARIES.
#   Debian 14 and macOS, 2.3.1 the config package wins -
#                              "Found GLEW: .../cmake/glew/glew-config.cmake" -
#                              and it exports the imported targets GLEW::glew
#                              and GLEW::glew_s WITHOUT setting the module
#                              variables. ${GLEW_LIBRARIES} then carried
#                              GLEW_LIBRARY-NOTFOUND, and the generate step
#                              stopped with "variables ... set to NOTFOUND:
#                              GLEW_LIBRARY" after configuring had said Found.
#
# So ask for a target first and fall back to the variable, rather than assuming
# one of the two ways GLEW can arrive.
if (TARGET GLEW::GLEW)
  set(TSC_GLEW_LIBRARIES GLEW::GLEW)      # CMake's FindGLEW module
elseif (TARGET GLEW::glew)
  set(TSC_GLEW_LIBRARIES GLEW::glew)      # GLEW's own config package, shared
elseif (TARGET GLEW::glew_s)
  set(TSC_GLEW_LIBRARIES GLEW::glew_s)    # ditto, static-only install
else()
  set(TSC_GLEW_LIBRARIES ${GLEW_LIBRARIES})
endif()
message(STATUS "GLEW links as: ${TSC_GLEW_LIBRARIES}")

# No cmake module for glm, do it manually. CEGUI needs glm.
find_path(GLM_HEADER NAMES glm/glm.hpp glm.hpp)
if (GLM_HEADER)
  message(STATUS "Found GLM: ${GLM_HEADER}")
else()
  message(SEND_ERROR "GLM header not found")
endif()

set(CEGUI_LIBRARIES "${TSC_BINARY_DIR}/cegui-install/lib/libCEGUIOpenGLRenderer-0_Static.a"
  "${TSC_BINARY_DIR}/cegui-install/lib/libCEGUIBase-0_Static.a"
  "${TSC_BINARY_DIR}/cegui-install/lib/libCEGUICoreWindowRendererSet_Static.a"
  "${TSC_BINARY_DIR}/cegui-install/lib/libCEGUIExpatParser_Static.a"
  "${TSC_BINARY_DIR}/cegui-install/lib/libCEGUIDevILImageCodec_Static.a")

# An ExternalProject is a SEPARATE cmake run: it inherits nothing from this one
# except what CMAKE_ARGS names. On macOS that is the difference between a build
# and a link error, because the architecture is a cache variable.
#
# Every macOS job failed here. Mac.yml configures TSC with
# -DCMAKE_OSX_ARCHITECTURES=arm64 (or x86_64), CEGUI's own cmake run never saw
# it, defaulted to x86_64, and linked against the arm64 Homebrew libraries
# beside it:
#
#   /usr/bin/c++ ... -arch x86_64 -mmacosx-version-min=13.0 -dynamiclib ...
#   Undefined symbols for architecture x86_64:
#   ld: symbol(s) not found for architecture x86_64
#
# It says "x86_64" even in the two arm64 jobs, which is what gives it away: the
# arch in that link line is not the one the job asked for. So the release got no
# .dmg at all - and no universal one either, since that job needs both halves.
#
# Only on Apple, and only when set: passing an empty CMAKE_OSX_ARCHITECTURES
# would pin the sub-build to "no architecture" rather than leave it at its
# default. The deployment target and sysroot travel with it for the same reason -
# a sub-build that targets a different macOS version than its parent produces
# libraries the parent cannot link either.
set(TSC_CEGUI_PLATFORM_ARGS "")
if (APPLE)
  foreach (osx_var CMAKE_OSX_ARCHITECTURES CMAKE_OSX_DEPLOYMENT_TARGET CMAKE_OSX_SYSROOT)
    if (${osx_var})
      # A multi-arch architecture value is a cmake LIST - "arm64;x86_64" - and a
      # list expanded into CMAKE_ARGS splits at the semicolon into two separate
      # arguments, so CEGUI would be configured with "-DCMAKE_OSX_ARCHITECTURES=arm64"
      # and a stray "x86_64". Encode it as | and let ExternalProject's
      # LIST_SEPARATOR below put the semicolon back.
      #
      # Mac.yml passes ONE arch per job today and welds the two builds with lipo
      # afterwards - a single-job universal build would need every Homebrew
      # dependency to be universal too - so this does not arise yet. It is here
      # because a silently split argument is not a thing to find out about later.
      string(REPLACE ";" "|" osx_value "${${osx_var}}")
      list(APPEND TSC_CEGUI_PLATFORM_ARGS "-D${osx_var}=${osx_value}")
    endif()
  endforeach()
  message(STATUS "CEGUI sub-build inherits: ${TSC_CEGUI_PLATFORM_ARGS}")
endif()

# CEGUI's SEPARATE cmake run uses its OWN bundled dependency finders, with their
# own cache variables (GLEW_LIB/GLEW_H_PATH, IL_LIB/IL_H_PATH), NOT the results of
# the outer find_package(GLEW)/find_package(DevIL) above. Both of those finders
# miss libraries the outer build found, and each miss is fatal in its own way:
#
#   * GLEW - the finder searches for a library named GLEW/glew. It misses it on
#     more than Windows (MSYS2 names it glew32; and it also missed on the Flatpak
#     runtime, where the outer build found it fine), and then reports
#       Could NOT find GLEW (missing: GLEW_LIB GLEW_H_PATH)
#     and stops the whole configure with
#       Building the old OpenGL renderer module is only supported using GLEW.
#
#   * DevIL - its finder misses IL_LIB, so the DevIL image codec COMPILES (its
#     headers are found, on macOS via the forwarded CMAKE_PREFIX_PATH below) but
#     links no libIL, and every macOS and Windows job died linking it with
#       Undefined symbols ... _ilInit    /    undefined reference to __imp_ilInit
#     Forwarding CMAKE_PREFIX_PATH alone did NOT fix this: the header was found,
#     the LIBRARY was still not on the link line, because IL_LIB was never set.
#
# So resolve BOTH by hand from what the OUTER build already found and hand them to
# CEGUI's cache variables. This runs on EVERY platform, because the same two
# finders miss on Flatpak (GLEW), on macOS and Windows (DevIL), and on armhf - a
# hint that names the library the outer build is already using cannot make a
# working finder worse, and it is the only thing that makes the failing ones pass.

# GLEW. The static archive too, for CEGUI's static configuration
# (CEGUI_BUILD_STATIC_CONFIGURATION=ON); where there is no separate static lib
# (typical on Linux/macOS) the shared one stands in - CEGUI only needs GLEW_LIB
# set to pass its configure check and compile the OpenGL renderer, the final TSC
# link provides the actual GLEW (TSC_GLEW_LIBRARIES).
find_path(TSC_CEGUI_GLEW_INC NAMES GL/glew.h HINTS ${GLEW_INCLUDE_DIRS})
find_library(TSC_CEGUI_GLEW_LIB NAMES glew32 GLEW glew HINTS "${GLEW_INCLUDE_DIRS}/../lib")
set(_saved_suffixes "${CMAKE_FIND_LIBRARY_SUFFIXES}")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
find_library(TSC_CEGUI_GLEW_LIB_STATIC NAMES glew32 glew32s GLEW glew HINTS "${GLEW_INCLUDE_DIRS}/../lib")
set(CMAKE_FIND_LIBRARY_SUFFIXES "${_saved_suffixes}")
if (NOT TSC_CEGUI_GLEW_LIB_STATIC)
  set(TSC_CEGUI_GLEW_LIB_STATIC "${TSC_CEGUI_GLEW_LIB}")
endif()
if (TSC_CEGUI_GLEW_INC AND TSC_CEGUI_GLEW_LIB)
  message(STATUS "CEGUI GLEW hint: lib=${TSC_CEGUI_GLEW_LIB} static=${TSC_CEGUI_GLEW_LIB_STATIC} inc=${TSC_CEGUI_GLEW_INC}")
  list(APPEND TSC_CEGUI_PLATFORM_ARGS
    "-DGLEW_H_PATH=${TSC_CEGUI_GLEW_INC}"
    "-DGLEW_LIB=${TSC_CEGUI_GLEW_LIB}"
    "-DGLEW_LIB_DBG=${TSC_CEGUI_GLEW_LIB}"
    "-DGLEW_LIB_STATIC=${TSC_CEGUI_GLEW_LIB_STATIC}"
    "-DGLEW_LIB_STATIC_DBG=${TSC_CEGUI_GLEW_LIB_STATIC}")
else()
  message(WARNING "GLEW not resolved for the CEGUI sub-build; its finder may still fail")
endif()

# DevIL (IL, and ILU). find_package(DevIL REQUIRED) above set IL_LIBRARIES /
# IL_INCLUDE_DIR / ILU_LIBRARIES; hand them to CEGUI's IL_LIB / IL_H_PATH /
# ILU_LIB so its DevIL image codec links libIL instead of leaving _il* undefined.
find_path(TSC_CEGUI_IL_INC NAMES IL/il.h HINTS ${IL_INCLUDE_DIR})
if (NOT TSC_CEGUI_IL_INC AND IL_INCLUDE_DIR)
  set(TSC_CEGUI_IL_INC "${IL_INCLUDE_DIR}")
endif()
# Prefer the exact library the outer find_package(DevIL) resolved; fall back to a
# find_library by name if it only exported an imported target.
set(TSC_CEGUI_IL_LIB "${IL_LIBRARIES}")
if (NOT TSC_CEGUI_IL_LIB)
  find_library(TSC_CEGUI_IL_LIB NAMES IL DevIL libIL HINTS "${TSC_CEGUI_IL_INC}/../lib")
endif()
set(TSC_CEGUI_ILU_LIB "${ILU_LIBRARIES}")
if (NOT TSC_CEGUI_ILU_LIB)
  find_library(TSC_CEGUI_ILU_LIB NAMES ILU HINTS "${TSC_CEGUI_IL_INC}/../lib")
endif()
if (TSC_CEGUI_IL_INC AND TSC_CEGUI_IL_LIB)
  message(STATUS "CEGUI DevIL hint: il=${TSC_CEGUI_IL_LIB} ilu=${TSC_CEGUI_ILU_LIB} inc=${TSC_CEGUI_IL_INC}")
  list(APPEND TSC_CEGUI_PLATFORM_ARGS
    "-DIL_H_PATH=${TSC_CEGUI_IL_INC}"
    "-DIL_LIB=${TSC_CEGUI_IL_LIB}")
  if (TSC_CEGUI_ILU_LIB)
    list(APPEND TSC_CEGUI_PLATFORM_ARGS "-DILU_LIB=${TSC_CEGUI_ILU_LIB}")
  endif()
else()
  message(WARNING "DevIL not resolved for the CEGUI sub-build; its DevIL image codec may not link libIL")
endif()

# The CEGUI sub-build is a separate cmake run, so it also does not inherit
# CMAKE_PREFIX_PATH - the prefix the outer build was told to search (Homebrew on
# macOS, from Mac.yml's -DCMAKE_PREFIX_PATH="$(brew --prefix)"). Without it CEGUI's
# DevIL image codec COMPILED (it found the DevIL headers) but linked no libIL, so
# every macOS job failed linking libCEGUIDevILImageCodec.dylib with
#   Undefined symbols for architecture x86_64: "_ilInit", "_ilLoadL", ...
# Forward the prefix so CEGUI's finders locate the same DevIL (and GLEW, freetype,
# ...) the outer build used. A cmake LIST is semicolon-separated; encode it as |
# and let ExternalProject's LIST_SEPARATOR put the semicolons back (see the arch
# note above).
if (CMAKE_PREFIX_PATH)
  string(REPLACE ";" "|" _tsc_cegui_prefix "${CMAKE_PREFIX_PATH}")
  list(APPEND TSC_CEGUI_PLATFORM_ARGS "-DCMAKE_PREFIX_PATH=${_tsc_cegui_prefix}")
  message(STATUS "CEGUI sub-build CMAKE_PREFIX_PATH: ${_tsc_cegui_prefix}")
endif()

ExternalProject_Add(
  cegui
  DOWNLOAD_COMMAND ${CMAKE_COMMAND} -E copy_directory "${TSC_SOURCE_DIR}/../cegui" "${TSC_BINARY_DIR}/cegui-source"
  SOURCE_DIR "${TSC_BINARY_DIR}/cegui-source"
  BINARY_DIR "${TSC_BINARY_DIR}/cegui-build"
  INSTALL_DIR "${TSC_BINARY_DIR}/cegui-install"
  PATCH_COMMAND patch -p1 < "${TSC_SOURCE_DIR}/../cegui-cpp11.patch" && patch -p1 < "${TSC_SOURCE_DIR}/../cegui-cmake-policy.patch"
  LIST_SEPARATOR |
  CMAKE_ARGS ${TSC_CEGUI_PLATFORM_ARGS} -Wno-dev -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=${TSC_BINARY_DIR}/cegui-install" -DCEGUI_BUILD_STATIC_CONFIGURATION=ON -DCEGUI_BUILD_STATIC_FACTORY_MODULE=ON -DCEGUI_BUILD_IMAGECODEC_DEVIL=ON -DCEGUI_BUILD_IMAGECODEC_SDL2=OFF -DCEGUI_BUILD_IMAGECODEC_FREEIMAGE=OFF -DCEGUI_BUILD_IMAGECODEC_CORONA=OFF -DCEGUI_BUILD_IMAGECODEC_PVR=OFF -DCEGUI_BUILD_IMAGECODEC_SILLY=OFF -DCEGUI_BUILD_IMAGECODEC_STB=OFF -DCEGUI_BUILD_IMAGECODEC_TGA=OFF -DCEGUI_BUILD_PYTHON_MODULES=OFF -DCEGUI_BUILD_LUA_GENERATOR=OFF -DCEGUI_BUILD_LUA_MODULE=OFF -DCEGUI_BUILD_XMLPARSER_EXPAT=ON -DCEGUI_BUILD_XMLPARSER_LIBXML2=OFF -DCEGUI_BUILD_XMLPARSER_RAPIDXML=OFF -DCEGUI_BUILD_XMLPARSER_XERCES=OFF -DCEGUI_BUILD_XMLPARSER_TINYXML=OFF -DCEGUI_BUILD_RENDERER_OPENGL=ON -DCEGUI_BUILD_RENDERER_OPENGL3=OFF -DCEGUI_BUILD_RENDERER_OPENGLES=OFF -DCEGUI_BUILD_RENDERER_DIRECT3D10=OFF -DCEGUI_BUILD_RENDERER_DIRECT3D11=OFF -DCEGUI_BUILD_RENDERER_DIRECT3D9=OFF -DCEGUI_BUILD_RENDERER_DIRECTFB=OFF -DCEGUI_BUILD_RENDERER_IRRLICHT=OFF -DCEGUI_BUILD_RENDERER_NULL=ON -DCEGUI_BUILD_RENDERER_OGRE=OFF -DCEGUI_SAMPLES_ENABLED=OFF -DCEGUI_BUILD_APPLICATION_TEMPLATES=OFF -DCEGUI_BUILD_TESTS=OFF -DCEGUI_WARNINGS_AS_ERRORS=OFF
  BUILD_BYPRODUCTS ${CEGUI_LIBRARIES})

set(CEGUI_LIBRARIES ${CEGUI_LIBRARIES}
  "${IL_LIBRARIES}"
  "${EXPAT_LIBRARIES}"
  "${FREETYPE_LIBRARIES}"
  ${TSC_GLEW_LIBRARIES})

set(CEGUI_INCLUDE_DIR "${TSC_BINARY_DIR}/cegui-install/include/cegui-0")
