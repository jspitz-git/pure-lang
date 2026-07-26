cmake_minimum_required(VERSION 3.25)

project(pure-ffi VERSION 0.16 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LIBFFI REQUIRED IMPORTED_TARGET "libffi>=3.4")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(ffi MODULE ffi.c)
target_link_libraries(
  ffi
  PRIVATE
    PkgConfig::PURE
    PkgConfig::LIBFFI
    PkgConfig::GMP
)
if(MINGW)
  target_link_options(ffi PRIVATE LINKER:--enable-auto-import)
endif()
set_target_properties(
  ffi
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
if(BUILD_TESTING)
  if(PURE_EXECUTABLE)
    if(NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "PURE_EXECUTABLE does not exist: ${PURE_EXECUTABLE}")
    endif()
    add_library(ffi-smoke-native SHARED tests/smoke-native.c)
    set_target_properties(
      ffi-smoke-native
      PROPERTIES
        PREFIX ""
        C_STANDARD 99
        C_STANDARD_REQUIRED ON
    )
    add_test(
      NAME pure-ffi-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:ffi>"
        "-DNATIVE_MODULE_DIR=$<TARGET_FILE_DIR:ffi-smoke-native>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
    )
    set_tests_properties(
      pure-ffi-smoke
      PROPERTIES
        LABELS "ffi;smoke"
        REQUIRED_FILES
          "$<TARGET_FILE:ffi>;$<TARGET_FILE:ffi-smoke-native>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    )
  else()
    message(STATUS "PURE_EXECUTABLE is not set; pure-ffi smoke test is disabled")
  endif()
endif()
