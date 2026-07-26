cmake_minimum_required(VERSION 3.25)

project(pure-mpfr VERSION 0.5 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(MPFR REQUIRED IMPORTED_TARGET "mpfr>=4.2")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(mpfr MODULE mpfr.c)
target_link_libraries(
  mpfr
  PRIVATE
    PkgConfig::PURE
    PkgConfig::MPFR
    PkgConfig::GMP
)
set_target_properties(
  mpfr
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
    add_test(
      NAME pure-mpfr-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:mpfr>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
    )
    set_tests_properties(
      pure-mpfr-smoke
      PROPERTIES
        LABELS "mpfr;smoke"
        REQUIRED_FILES
          "$<TARGET_FILE:mpfr>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    )
  else()
    message(STATUS "PURE_EXECUTABLE is not set; pure-mpfr smoke test is disabled")
  endif()
endif()
