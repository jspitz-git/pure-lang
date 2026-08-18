cmake_minimum_required(VERSION 3.25)
project(pure_fastcgi C)

if(NOT WIN32)
  message(FATAL_ERROR "pure-fastcgi requires Windows")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)
pkg_check_modules(MPFR REQUIRED IMPORTED_TARGET mpfr)

set(PURE_FASTCGI_FCGI2_ARCHIVE "" CACHE FILEPATH
  "Absolute path to the verified fcgi2 source archive")
if(NOT IS_ABSOLUTE "${PURE_FASTCGI_FCGI2_ARCHIVE}"
    OR NOT EXISTS "${PURE_FASTCGI_FCGI2_ARCHIVE}")
  message(FATAL_ERROR
    "PURE_FASTCGI_FCGI2_ARCHIVE must name an existing absolute file")
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Fcgi2Dependency.cmake")
pure_fastcgi_prepare_fcgi2(
  ARCHIVE "${PURE_FASTCGI_FCGI2_ARCHIVE}"
  OUT_SOURCE_DIR fcgi2_source)
pure_fastcgi_add_fcgi2_target(SOURCE_DIR "${fcgi2_source}")

add_library(pure-fastcgi MODULE fastcgi.c fastcgi_extra.c)
set_target_properties(pure-fastcgi PROPERTIES
  OUTPUT_NAME fastcgi
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_compile_features(pure-fastcgi PRIVATE c_std_11)
target_link_libraries(pure-fastcgi PRIVATE
  fcgi2-static
  PkgConfig::PURE
  PkgConfig::GMP
  PkgConfig::MPFR)

include(CTest)
find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
find_program(LLVM_NM NAMES llvm-nm REQUIRED)
add_custom_target(
  verify-windows-dependencies
  COMMAND "${CMAKE_COMMAND}"
    "-DLLVM_READOBJ=${LLVM_READOBJ}"
    "-DLLVM_NM=${LLVM_NM}"
    "-DMODULE=$<TARGET_FILE:pure-fastcgi>"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
  DEPENDS pure-fastcgi
  COMMENT "Verifying the pure-fastcgi Windows dependency closure"
  VERBATIM)

if(BUILD_TESTING)
  add_test(
    NAME pure-fastcgi-source-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DFCGI2_ARCHIVE=${PURE_FASTCGI_FCGI2_ARCHIVE}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/source-contract"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/source-contract.cmake")
  set_tests_properties(pure-fastcgi-source-contract PROPERTIES
    LABELS "fastcgi;source;contract"
    TIMEOUT 30)
endif()
