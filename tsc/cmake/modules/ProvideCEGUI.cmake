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

ExternalProject_Add(
  cegui
  DOWNLOAD_COMMAND ${CMAKE_COMMAND} -E copy_directory "${TSC_SOURCE_DIR}/../cegui" "${TSC_BINARY_DIR}/cegui-source"
  SOURCE_DIR "${TSC_BINARY_DIR}/cegui-source"
  BINARY_DIR "${TSC_BINARY_DIR}/cegui-build"
  INSTALL_DIR "${TSC_BINARY_DIR}/cegui-install"
  PATCH_COMMAND patch -p1 < "${TSC_SOURCE_DIR}/../cegui-cpp11.patch" && patch -p1 < "${TSC_SOURCE_DIR}/../cegui-cmake-policy.patch"
  CMAKE_ARGS -Wno-dev -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=${TSC_BINARY_DIR}/cegui-install" -DCEGUI_BUILD_STATIC_CONFIGURATION=ON -DCEGUI_BUILD_STATIC_FACTORY_MODULE=ON -DCEGUI_BUILD_IMAGECODEC_DEVIL=ON -DCEGUI_BUILD_IMAGECODEC_SDL2=OFF -DCEGUI_BUILD_IMAGECODEC_FREEIMAGE=OFF -DCEGUI_BUILD_IMAGECODEC_CORONA=OFF -DCEGUI_BUILD_IMAGECODEC_PVR=OFF -DCEGUI_BUILD_IMAGECODEC_SILLY=OFF -DCEGUI_BUILD_IMAGECODEC_STB=OFF -DCEGUI_BUILD_IMAGECODEC_TGA=OFF -DCEGUI_BUILD_PYTHON_MODULES=OFF -DCEGUI_BUILD_LUA_GENERATOR=OFF -DCEGUI_BUILD_LUA_MODULE=OFF -DCEGUI_BUILD_XMLPARSER_EXPAT=ON -DCEGUI_BUILD_XMLPARSER_LIBXML2=OFF -DCEGUI_BUILD_XMLPARSER_RAPIDXML=OFF -DCEGUI_BUILD_XMLPARSER_XERCES=OFF -DCEGUI_BUILD_XMLPARSER_TINYXML=OFF -DCEGUI_BUILD_RENDERER_OPENGL=ON -DCEGUI_BUILD_RENDERER_OPENGL3=OFF -DCEGUI_BUILD_RENDERER_OPENGLES=OFF -DCEGUI_BUILD_RENDERER_DIRECT3D10=OFF -DCEGUI_BUILD_RENDERER_DIRECT3D11=OFF -DCEGUI_BUILD_RENDERER_DIRECT3D9=OFF -DCEGUI_BUILD_RENDERER_DIRECTFB=OFF -DCEGUI_BUILD_RENDERER_IRRLICHT=OFF -DCEGUI_BUILD_RENDERER_NULL=ON -DCEGUI_BUILD_RENDERER_OGRE=OFF -DCEGUI_SAMPLES_ENABLED=OFF -DCEGUI_BUILD_APPLICATION_TEMPLATES=OFF -DCEGUI_BUILD_TESTS=OFF -DCEGUI_WARNINGS_AS_ERRORS=OFF
  BUILD_BYPRODUCTS ${CEGUI_LIBRARIES})

set(CEGUI_LIBRARIES ${CEGUI_LIBRARIES}
  "${IL_LIBRARIES}"
  "${EXPAT_LIBRARIES}"
  "${FREETYPE_LIBRARIES}"
  ${TSC_GLEW_LIBRARIES})

set(CEGUI_INCLUDE_DIR "${TSC_BINARY_DIR}/cegui-install/include/cegui-0")
