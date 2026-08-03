if (USE_SYSTEM_MRUBY)
  find_path(MRuby_INCLUDE_DIR mruby.h)
  find_library(MRuby_LIBRARIES mruby mruby_core)

  message("-- Scripting engine enabled; found mruby at ${MRuby_LIBRARIES}")
else()
  message("-- Scripting engine enabled: building mruby statically")

  # mruby requires gperf, Bison and ruby to compile.
  find_package(BISON REQUIRED)
  find_package(Ruby REQUIRED)

  find_program(GPERF gperf)
  if (GPERF)
    message(STATUS "Found gperf: ${GPERF}")
  else()
    message(SEND_ERROR "gperf not found")
  endif()

  set(MRuby_LIBRARIES "${TSC_BINARY_DIR}/mruby/build/host/lib/libmruby.a" "${TSC_BINARY_DIR}/mruby/build/host/lib/libmruby_core.a")

  # Run minirake through the interpreter, not as a program.
  #
  # `minirake` is a Ruby script with no extension. On Linux and macOS its shebang
  # makes `./minirake` work, so this was never noticed there. On Windows the
  # generator turns it into `.\minirake` and hands it to cmd, which has no
  # shebangs and no idea what to do with an extensionless file:
  #
  #   '.\minirake' is not recognized as an internal or external command,
  #   operable program or batch file.
  #
  # That is what stopped every win64 build - and it stopped the whole ninja run,
  # so the release got no Windows installer at all. find_package(Ruby) above
  # already located an interpreter (it is REQUIRED), so name it. CMake's FindRuby
  # sets Ruby_EXECUTABLE from 3.18 and RUBY_EXECUTABLE before that, and still
  # sets the old one for compatibility; take whichever is there.
  if (DEFINED Ruby_EXECUTABLE AND Ruby_EXECUTABLE)
    set(TSC_RUBY_EXECUTABLE "${Ruby_EXECUTABLE}")
  else()
    set(TSC_RUBY_EXECUTABLE "${RUBY_EXECUTABLE}")
  endif()
  message(STATUS "Building mruby with ${TSC_RUBY_EXECUTABLE} ./minirake")

  ExternalProject_Add(
    mruby
    DOWNLOAD_COMMAND ${CMAKE_COMMAND} -E copy_directory "${TSC_SOURCE_DIR}/../mruby/mruby" "${TSC_BINARY_DIR}/mruby"
    PATCH_COMMAND patch -p1 < "${TSC_SOURCE_DIR}/../mruby-werror.patch"
    SOURCE_DIR "${TSC_BINARY_DIR}/mruby"
    CONFIGURE_COMMAND ""
    BUILD_IN_SOURCE 1
    BUILD_COMMAND ${TSC_RUBY_EXECUTABLE} ./minirake MRUBY_CONFIG=${TSC_SOURCE_DIR}/mruby_tsc_build_config.rb TSC_BUILD_TYPE="${CMAKE_BUILD_TYPE}"
    BUILD_BYPRODUCTS ${MRuby_LIBRARIES}
    INSTALL_COMMAND "")

  set(MRuby_INCLUDE_DIR ${TSC_SOURCE_DIR}/../mruby/mruby/include)
endif()
