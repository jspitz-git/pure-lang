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
  add_test(
    NAME pure-faust-runtime-layout
    COMMAND "${CMAKE_COMMAND}"
      "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DSTAGE_PREFIX=${runtime_stage}"
      "-DEXPECT_DEVELOPER=OFF"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
  set_tests_properties(pure-faust-runtime-layout PROPERTIES
    LABELS "faust;runtime;layout"
    TIMEOUT 30)

  if(WIN32)
    find_program(PURE_FAUST_POWERSHELL_EXECUTABLE NAMES powershell.exe pwsh.exe REQUIRED)
    add_test(
      NAME pure-faust-helper-failures
      COMMAND "${CMAKE_COMMAND}"
        "-DPOWERSHELL_EXECUTABLE=${PURE_FAUST_POWERSHELL_EXECUTABLE}"
        "-DHELPER_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tools/faust2pure.ps1"
        "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/helper failures"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/helper-failures.cmake")
    set_tests_properties(pure-faust-helper-failures PROPERTIES
      LABELS "faust;developer;helper"
      TIMEOUT 30)

    if(PURE_FAUST_DEVELOPER_AVAILABLE)
      set(developer_stage "${CMAKE_CURRENT_BINARY_DIR}/developer stage")
      add_test(
        NAME pure-faust-developer-smoke
        COMMAND "${CMAKE_COMMAND}"
          "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
          "-DPURE_PREFIX=${PURE_PREFIX}"
          "-DRUNTIME_SMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime-smoke.pure"
          "-DSTAGE_PREFIX=${developer_stage}"
          "-DEXPECT_DEVELOPER=ON"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyInstalledPackage.cmake")
      add_test(
        NAME pure-faust-developer-content-audit-failures
        COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/developer audit mutation"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/developer-content-audit-failures.cmake")
      add_test(
        NAME pure-faust-developer-header-closure
        COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/compiler-header-closure.cmake")
      add_test(
        NAME pure-faust-developer-allowlist-failures
        COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DAUTHORITATIVE_MANIFEST=${PURE_FAUST_AUTHORITATIVE_MANIFEST}"
          "-DSTAGE_PREFIX=${developer_stage}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/developer-allowlist-failures.cmake")
      set_tests_properties(pure-faust-developer-smoke PROPERTIES
        LABELS "faust;developer;layout;smoke"
        TIMEOUT 180)
      set_property(TEST pure-faust-developer-smoke PROPERTY
        ENVIRONMENT_MODIFICATION
          "Path=set:${developer_stage}/bin\;C:/Windows/System32/WindowsPowerShell/v1.0\;C:/Windows/System32\;C:/Windows")
      set_tests_properties(pure-faust-developer-content-audit-failures
        PROPERTIES LABELS "faust;developer;failure;audit" TIMEOUT 30)
      set_tests_properties(pure-faust-developer-header-closure
        PROPERTIES LABELS "faust;developer;headers" TIMEOUT 30)
      set_tests_properties(pure-faust-developer-allowlist-failures PROPERTIES
        DEPENDS pure-faust-developer-smoke
        LABELS "faust;developer;failure;allowlist"
        TIMEOUT 30)
    endif()

    set(runtime_smoke_stage "${CMAKE_CURRENT_BINARY_DIR}/runtime smoke stage")
    add_test(
      NAME pure-faust-runtime-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DSTAGE_PREFIX=${runtime_smoke_stage}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_PREFIX=${PURE_PREFIX}"
        "-DFIXTURE_BASE=${runtime_smoke_stage}/share/doc/pure-faust/tests/reference"
        "-DRUNTIME_SMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime-smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunRuntimeSmoke.cmake")
    set_tests_properties(pure-faust-runtime-smoke PROPERTIES
      LABELS "faust;runtime;smoke"
      TIMEOUT 120)

    add_test(
      NAME pure-faust-runtime-smoke-failures
      COMMAND "${CMAKE_COMMAND}"
        "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DSTAGE_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/missing fixture stage"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_PREFIX=${PURE_PREFIX}"
        "-DMISSING_FIXTURE_BASE=${CMAKE_CURRENT_BINARY_DIR}/missing fixture stage/share/doc/pure-faust/tests/missing"
        "-DRUNTIME_SMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime-smoke.pure"
        "-DFALSE_PASS_STAGE_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/false pass stage"
        "-DFALSE_PASS_FIXTURE_BASE=${CMAKE_CURRENT_BINARY_DIR}/false pass stage/share/doc/pure-faust/tests/reference"
        "-DFALSE_PASS_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime-smoke-false-pass.pure"
        "-DDRIVER_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunRuntimeSmoke.cmake"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime-smoke-failures.cmake")
    set_tests_properties(pure-faust-runtime-smoke-failures PROPERTIES
      LABELS "faust;runtime;smoke;failure"
      TIMEOUT 120)
  endif()
endif()
