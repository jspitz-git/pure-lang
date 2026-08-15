cmake_minimum_required(VERSION 3.25)

project(pure-faust VERSION 0.11 LANGUAGES NONE)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_get_variable(PURE_PREFIX pure prefix)
find_program(
  PURE_EXECUTABLE
  NAMES pure.exe pure
  HINTS "${PURE_PREFIX}/bin"
  NO_DEFAULT_PATH
  REQUIRED)

set(PURE_FAUST_CORE_FIXTURE "" CACHE FILEPATH
  "Compatible Faust bitcode fixture supplied by the Pure core build")
set(PURE_FAUST_FAUST_ROOT "" CACHE PATH
  "Root of the extracted Faust developer component")
set(PURE_FAUST_CLANG "" CACHE FILEPATH
  "Distribution-owned Clang executable for the Faust developer component")
set(PURE_FAUST_OPT "" CACHE FILEPATH
  "Distribution-owned opt executable for the Faust developer component")

include(CTest)
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

if(BUILD_TESTING)
  set(runtime_stage "${CMAKE_CURRENT_BINARY_DIR}/stage runtime")
  set(runtime_smoke_stage "${CMAKE_CURRENT_BINARY_DIR}/runtime smoke stage")
  add_test(
    NAME pure-faust-runtime-layout
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DSTAGE_PREFIX=${runtime_smoke_stage}"
      "-DEXPECT_DEVELOPER=OFF"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
  set_tests_properties(pure-faust-runtime-layout PROPERTIES
    LABELS "faust;runtime;layout"
    TIMEOUT 30)

  add_test(
    NAME pure-faust-runtime-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DSTAGE_PREFIX=${runtime_stage}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DRUNTIME_SMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime-smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunRuntimeSmoke.cmake")
  set_tests_properties(pure-faust-runtime-smoke PROPERTIES
    LABELS "faust;runtime;smoke"
    TIMEOUT 120)
endif()
