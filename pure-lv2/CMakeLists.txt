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

if(BUILD_TESTING)
  add_test(
    NAME pure-lv2-module-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:lv2>"
      "-DPURE_RUNTIME_DIR=${PURE_PREFIX}/bin"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunModuleTest.cmake")
  set_tests_properties(pure-lv2-module-load PROPERTIES
    LABELS "pure-lv2;module;windows"
    REQUIRED_FILES "$<TARGET_FILE:lv2>;${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
    TIMEOUT 30)
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
endif()
