cmake_minimum_required(VERSION 3.25)

project(pure-lv2 VERSION 0.2 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LV2 REQUIRED IMPORTED_TARGET "lv2>=1.18.2")

add_library(lv2 MODULE lv2.c)
target_compile_features(lv2 PRIVATE c_std_99)
target_compile_options(lv2 PRIVATE -Wall -Wextra)
target_link_libraries(lv2 PRIVATE PkgConfig::PURE)
set_target_properties(lv2 PROPERTIES
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)

# Keep the generic bridge buildable even before a concrete plugin supplies
# its loader. Source mode avoids an unresolved batch-loader symbol here.
add_library(lv2pure-compile-check OBJECT lv2pure.c)
target_compile_features(lv2pure-compile-check PRIVATE c_std_99)
target_compile_options(lv2pure-compile-check PRIVATE
  -Wall
  -Wextra
  -Wno-unused-parameter
  -Wno-unused-function
  -Wno-dll-attribute-on-redeclaration)
target_compile_definitions(lv2pure-compile-check PRIVATE
  DLLEXT=".dll"
  URI_PREFIX="urn:pure-lang:compile-check/"
  PLUGIN_NAME="pure-lv2"
  PLUGIN_SCRIPT="compile-check.pure")
target_link_libraries(lv2pure-compile-check PRIVATE
  PkgConfig::PURE
  PkgConfig::LV2)

pkg_get_variable(PURE_PREFIX pure prefix)
find_program(PURE_EXECUTABLE
  NAMES pure
  HINTS "${PURE_PREFIX}/bin"
  NO_DEFAULT_PATH
  REQUIRED)
get_filename_component(PURE_RUNTIME_BIN_DIR "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(PURE_INSTALL_PREFIX "${PURE_RUNTIME_BIN_DIR}" DIRECTORY)

set(PURE_LILV_MODULE "" CACHE FILEPATH
  "Path to the Windows pure-lilv module used by integration tests")
set(PURE_LILV_SOURCE
  "${CMAKE_CURRENT_SOURCE_DIR}/../pure-lilv/lilv.pure"
  CACHE FILEPATH "Path to the pure-lilv source module")
set(LILV_DLL "" CACHE FILEPATH "Path to liblilv-0.dll")
set(SERD_DLL "" CACHE FILEPATH "Path to libserd-0.dll")
set(SORD_DLL "" CACHE FILEPATH "Path to libsord-0.dll")
set(SRATOM_DLL "" CACHE FILEPATH "Path to libsratom-0.dll")
set(ZIX_DLL "" CACHE FILEPATH "Path to libzix-0.dll")
set(PURE2LV2_CC "" CACHE FILEPATH
  "C compiler used by the pure2lv2 integration test")
set(PURE2LV2_TOOL_DIR "" CACHE PATH
  "Directory containing LLVM tools used by pure2lv2")
set(PURE2LV2_LV2_INCLUDE "" CACHE PATH
  "Include root containing the LV2 headers")

if(BUILD_TESTING)
  add_test(
    NAME pure-lv2-module-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:lv2>"
      "-DPURE_RUNTIME_DIR=${PURE_RUNTIME_BIN_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunModuleTest.cmake")
  set_tests_properties(pure-lv2-module-load PROPERTIES
    LABELS "pure-lv2;module;windows"
    REQUIRED_FILES "$<TARGET_FILE:lv2>;${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
    TIMEOUT 30)

  if(WIN32)
    set(POWERSHELL_EXECUTABLE
      "$ENV{SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe")
    if(NOT EXISTS "${POWERSHELL_EXECUTABLE}")
      message(FATAL_ERROR "Windows PowerShell not found: ${POWERSHELL_EXECUTABLE}")
    endif()
    add_test(
      NAME pure-lv2-native-generator-help
      COMMAND "${POWERSHELL_EXECUTABLE}"
        -NoProfile -ExecutionPolicy Bypass
        -File "${CMAKE_CURRENT_SOURCE_DIR}/pure2lv2.ps1" --help)
    set_tests_properties(pure-lv2-native-generator-help PROPERTIES
      LABELS "pure-lv2;generator;windows"
      PASS_REGULAR_EXPRESSION "USAGE: pure2lv2"
      TIMEOUT 15)
  endif()
endif()

if(WIN32)
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPURE_LV2_MODULE=$<TARGET_FILE:lv2>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS lv2 lv2pure-compile-check
    COMMENT "Verifying the pure-lv2 Windows module"
    VERBATIM)

  if(BUILD_TESTING)
    set(_pure_lv2_integration_inputs
      PURE_LILV_MODULE PURE_LILV_SOURCE LILV_DLL SERD_DLL SORD_DLL
      SRATOM_DLL ZIX_DLL PURE2LV2_CC PURE2LV2_TOOL_DIR
      PURE2LV2_LV2_INCLUDE)
    set(_pure_lv2_can_integrate TRUE)
    foreach(_input IN LISTS _pure_lv2_integration_inputs)
      if(NOT ${_input})
        set(_pure_lv2_can_integrate FALSE)
      endif()
    endforeach()

    if(_pure_lv2_can_integrate)
      add_test(
        NAME pure-lv2-generated-plugins
        COMMAND "${CMAKE_COMMAND}"
          "-DBUILD_ROOT=${CMAKE_CURRENT_BINARY_DIR}"
          "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/pure-lv2 integration"
          "-DPURE_BASE_PREFIX=${PURE_INSTALL_PREFIX}"
          "-DPURE_LV2_MODULE=$<TARGET_FILE:lv2>"
          "-DPURE_LV2_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DPURE_LILV_MODULE=${PURE_LILV_MODULE}"
          "-DPURE_LILV_SOURCE=${PURE_LILV_SOURCE}"
          "-DLILV_DLL=${LILV_DLL}"
          "-DSERD_DLL=${SERD_DLL}"
          "-DSORD_DLL=${SORD_DLL}"
          "-DSRATOM_DLL=${SRATOM_DLL}"
          "-DZIX_DLL=${ZIX_DLL}"
          "-DPURE2LV2_CC=${PURE2LV2_CC}"
          "-DPURE2LV2_TOOL_DIR=${PURE2LV2_TOOL_DIR}"
          "-DPURE2LV2_LV2_INCLUDE=${PURE2LV2_LV2_INCLUDE}"
          "-DPOWERSHELL_EXECUTABLE=${POWERSHELL_EXECUTABLE}"
          "-DLLVM_READOBJ=${LLVM_READOBJ}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunIntegrationTest.cmake")
      set_tests_properties(pure-lv2-generated-plugins PROPERTIES
        LABELS
          "pure-lv2;generator;batch;source;dynmanifest;processing;lifecycle;windows"
        REQUIRED_FILES
          "$<TARGET_FILE:lv2>;${PURE_LILV_MODULE};${PURE_LILV_SOURCE}"
        TIMEOUT 150)
    else()
      message(STATUS
        "pure-lv2 generated-plugin integration test disabled; "
        "set ${_pure_lv2_integration_inputs}")
    endif()
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
