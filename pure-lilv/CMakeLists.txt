cmake_minimum_required(VERSION 3.25)

project(pure-lilv VERSION 0.5 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LV2 REQUIRED IMPORTED_TARGET "lv2>=1.18.2")
pkg_check_modules(SERD REQUIRED IMPORTED_TARGET "serd-0>=0.30.10")
pkg_check_modules(SORD REQUIRED IMPORTED_TARGET "sord-0>=0.16.20")
pkg_check_modules(SRATOM REQUIRED IMPORTED_TARGET "sratom-0>=0.6.10")
pkg_check_modules(ZIX REQUIRED IMPORTED_TARGET "zix-0>=0.6.0")

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/LilvDependency.cmake")

add_library(lilv MODULE lilv.c lv2_evbuf.c symap.c)
target_compile_features(lilv PRIVATE c_std_99)
target_compile_options(lilv PRIVATE
  -Wall
  -Wextra
  -Wno-deprecated-declarations
  -Wno-sign-compare
  -Wno-unused-parameter
  -Wno-unused-variable)
target_link_libraries(lilv PRIVATE
  Lilv::lilv
  PkgConfig::PURE
  PkgConfig::LV2
  PkgConfig::SERD)
set_target_properties(lilv PROPERTIES
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(BUILD_TESTING)
  set(test_lv2_root "${CMAKE_CURRENT_BINARY_DIR}/test-lv2")
  set(static_bundle "${test_lv2_root}/static-gain.lv2")
  set(dynamic_bundle "${test_lv2_root}/dynamic-gain.lv2")
  file(MAKE_DIRECTORY "${static_bundle}" "${dynamic_bundle}")
  configure_file(
    tests/static-gain.lv2/manifest.ttl
    "${static_bundle}/manifest.ttl"
    COPYONLY)
  configure_file(
    tests/static-gain.lv2/gain.ttl
    "${static_bundle}/gain.ttl"
    COPYONLY)
  configure_file(
    tests/dynamic-gain.lv2/manifest.ttl
    "${dynamic_bundle}/manifest.ttl"
    COPYONLY)

  add_library(static-gain MODULE tests/test-gain.c)
  target_link_libraries(static-gain PRIVATE PkgConfig::LV2)
  set_target_properties(static-gain PROPERTIES
    PREFIX ""
    OUTPUT_NAME "static-gain"
    RUNTIME_OUTPUT_DIRECTORY "${static_bundle}"
    LIBRARY_OUTPUT_DIRECTORY "${static_bundle}")

  add_library(dynamic-gain MODULE tests/test-gain.c)
  target_compile_definitions(dynamic-gain PRIVATE
    TEST_DYNAMIC_MANIFEST
    TEST_GAIN_URI="urn:pure-lang:test:dynamic-gain")
  target_compile_options(dynamic-gain PRIVATE -Wno-dll-attribute-on-redeclaration)

  target_link_libraries(dynamic-gain PRIVATE PkgConfig::LV2)
  set_target_properties(dynamic-gain PROPERTIES
    PREFIX ""
    OUTPUT_NAME "dynamic-gain"
    RUNTIME_OUTPUT_DIRECTORY "${dynamic_bundle}"
    LIBRARY_OUTPUT_DIRECTORY "${dynamic_bundle}")

  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED)
  set(empty_lv2_root "${CMAKE_CURRENT_BINARY_DIR}/empty-lv2")
  set(preset_root "${CMAKE_CURRENT_BINARY_DIR}/preset-work")
  file(MAKE_DIRECTORY "${empty_lv2_root}" "${preset_root}")
  add_test(
    NAME pure-lilv-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:lilv>"
      "-DPURE_RUNTIME_DIR=${PURE_PREFIX}/bin"
      "-DLILV_RUNTIME_DIR=${LILV_PREFIX}/bin"
      "-DDEPENDENCY_RUNTIME_DIR=${SERD_PREFIX}/bin"
      "-DEMPTY_LV2_ROOT=${empty_lv2_root}"
      "-DTEST_LV2_ROOT=${test_lv2_root}"
      "-DPRESET_ROOT=${preset_root}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake")
  set_tests_properties(pure-lilv-smoke PROPERTIES
    LABELS "lilv;lv2;discovery;dynmanifest;processing;state;lifecycle"
    REQUIRED_FILES
      "$<TARGET_FILE:lilv>;$<TARGET_FILE:static-gain>;$<TARGET_FILE:dynamic-gain>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    TIMEOUT 60)
endif()

if(WIN32)
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPURE_LILV_MODULE=$<TARGET_FILE:lilv>"
      "-DLILV_DLL=${LILV_RUNTIME_DLL}"
      "-DSERD_DLL=${SERD_RUNTIME_DLL}"
      "-DSORD_DLL=${SORD_RUNTIME_DLL}"
      "-DSRATOM_DLL=${SRATOM_RUNTIME_DLL}"
      "-DZIX_DLL=${ZIX_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS lilv lilv-external
    COMMENT "Verifying the pure-lilv Windows dependency closure"
    VERBATIM)
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
