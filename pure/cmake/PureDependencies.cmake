include_guard(GLOBAL)

find_package(BISON 3.0 REQUIRED)
find_package(FLEX 2.6 REQUIRED)
find_package(Iconv REQUIRED)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)

pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)
pkg_check_modules(MPFR REQUIRED IMPORTED_TARGET mpfr)
pkg_check_modules(READLINE REQUIRED IMPORTED_TARGET readline)
pkg_check_modules(PCREPOSIX REQUIRED IMPORTED_TARGET libpcreposix)

if(PURE_STRICT_TOOLCHAIN AND WIN32)
  pure_require_clang64_path("${PKG_CONFIG_EXECUTABLE}" "pkg-config")

  foreach(package GMP MPFR READLINE PCREPOSIX)
    foreach(path_kind PREFIX INCLUDE_DIRS LIBRARY_DIRS LINK_LIBRARIES)
      foreach(package_path IN LISTS ${package}_${path_kind})
        if(NOT path_kind STREQUAL "LINK_LIBRARIES" OR
           IS_ABSOLUTE "${package_path}")
          pure_require_clang64_path(
            "${package_path}" "${package} ${path_kind} path"
          )
        endif()
      endforeach()
    endforeach()
  endforeach()

  if(Iconv_IS_BUILT_IN OR NOT Iconv_INCLUDE_DIRS OR NOT Iconv_LIBRARIES)
    message(FATAL_ERROR
      "The Windows release build requires the external CLANG64 iconv package"
    )
  endif()
  foreach(iconv_path IN LISTS Iconv_INCLUDE_DIRS Iconv_LIBRARIES)
    pure_require_clang64_path("${iconv_path}" "iconv path")
  endforeach()
endif()

pkg_check_modules(GSL QUIET IMPORTED_TARGET gsl)

if(APPLE)
  # The SDK's usr/include is already searched through Clang's sysroot. Some
  # imported system-library targets add it explicitly, which places the C
  # headers before libc++ and breaks the wrapper headers' include_next calls.
  get_property(PURE_IMPORTED_TARGETS DIRECTORY PROPERTY IMPORTED_TARGETS)
  foreach(imported_target IN LISTS PURE_IMPORTED_TARGETS)
    get_target_property(
      imported_includes "${imported_target}" INTERFACE_INCLUDE_DIRECTORIES
    )
    if(imported_includes)
      set(filtered_includes ${imported_includes})
      list(
        FILTER filtered_includes EXCLUDE
        REGEX "/MacOSX[^/]*\\.sdk/usr/include/?$"
      )
      set_property(
        TARGET "${imported_target}"
        PROPERTY INTERFACE_INCLUDE_DIRECTORIES "${filtered_includes}"
      )
    endif()
  endforeach()
endif()

find_program(PURE_FAUST_EXECUTABLE NAMES faust)
find_program(PURE_FLANG_EXECUTABLE NAMES flang flang-new flang-22 flang-new-22)
find_program(PURE_GFORTRAN_EXECUTABLE NAMES gfortran)
find_program(PURE_SPHINX_BUILD NAMES sphinx-build)

message(STATUS "Bison: ${BISON_VERSION} (${BISON_EXECUTABLE})")
message(STATUS "Flex: ${FLEX_VERSION} (${FLEX_EXECUTABLE})")
message(STATUS "GMP: ${GMP_VERSION}")
message(STATUS "MPFR: ${MPFR_VERSION}")
message(STATUS "readline: ${READLINE_VERSION}")
message(STATUS "PCRE POSIX: ${PCREPOSIX_VERSION}")

if(GSL_FOUND)
  message(STATUS "GSL: ${GSL_VERSION}")
else()
  message(STATUS "GSL: not found; bitcode examples requiring GSL will be disabled")
endif()

if(PURE_FAUST_EXECUTABLE)
  message(STATUS "Faust: ${PURE_FAUST_EXECUTABLE}")
else()
  message(STATUS "Faust: not found; Faust integration fixtures will be disabled")
endif()

if(PURE_FLANG_EXECUTABLE)
  message(STATUS "Flang: ${PURE_FLANG_EXECUTABLE}")
else()
  message(STATUS "Flang: not found; Fortran bitcode fixtures will be disabled")
endif()

if(PURE_GFORTRAN_EXECUTABLE)
  message(STATUS "GFortran: ${PURE_GFORTRAN_EXECUTABLE}")
else()
  message(STATUS "GFortran: not found; native Fortran examples will be disabled")
endif()

if(PURE_SPHINX_BUILD)
  message(STATUS "Sphinx: ${PURE_SPHINX_BUILD}")
else()
  message(STATUS "Sphinx: not found; documentation targets will be disabled")
endif()
