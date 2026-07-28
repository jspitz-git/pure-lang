cmake_minimum_required(VERSION 3.25)

project(pure-tk VERSION 0.5 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_get_variable(TCL_PREFIX tcl prefix)

find_path(
  TCL_INCLUDE_DIR
  NAMES tcl.h tk.h
  HINTS "${TCL_PREFIX}/include"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  TCL_LIBRARY
  NAMES tcl86 tcl
  HINTS "${TCL_PREFIX}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  TK_LIBRARY
  NAMES tk86 tk
  HINTS "${TCL_PREFIX}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)

foreach(runtime IN ITEMS TCL:tcl86.dll TK:tk86.dll ZLIB:zlib1.dll)
  string(REPLACE ":" ";" runtime_pair "${runtime}")
  list(GET runtime_pair 0 runtime_name)
  list(GET runtime_pair 1 runtime_file)
  find_file(
    "${runtime_name}_RUNTIME_DLL"
    NAMES "${runtime_file}"
    HINTS "${TCL_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
endforeach()
add_library(pure-tk MODULE tk.c)
target_compile_features(pure-tk PRIVATE c_std_11)
target_include_directories(pure-tk PRIVATE "${TCL_INCLUDE_DIR}")
target_compile_options(pure-tk PRIVATE -Wall -Wextra -Werror)
target_link_libraries(
  pure-tk
  PRIVATE
    PkgConfig::PURE
    "${TCL_LIBRARY}"
    "${TK_LIBRARY}"
)
set_target_properties(
  pure-tk
  PROPERTIES
    OUTPUT_NAME tk
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
if(WIN32)
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPURE_TK_MODULE=$<TARGET_FILE:pure-tk>"
      "-DTCL_DLL=${TCL_RUNTIME_DLL}"
      "-DTK_DLL=${TK_RUNTIME_DLL}"
      "-DZLIB_DLL=${ZLIB_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS pure-tk
    COMMENT "Verifying the pure-tk Windows dependency closure"
    VERBATIM
  )
endif()
include(CTest)
if(BUILD_TESTING AND WIN32)
  pkg_get_variable(PURE_PREFIX pure prefix)
  add_test(
    NAME pure-tk-relocatable
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DMODULE_FILE=$<TARGET_FILE:pure-tk>"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DTCL_PREFIX=${TCL_PREFIX}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/relocatable.pure"
      "-DEXPECTED_MARKER=PURE_TK_RELOCATABLE_OK"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/relocatable-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunRelocatableTest.cmake"
  )
  set_tests_properties(
    pure-tk-relocatable
    PROPERTIES
      LABELS "tk;relocatable;discovery;encoding;sanitized"
      REQUIRED_FILES
        "$<TARGET_FILE:pure-tk>;${CMAKE_CURRENT_SOURCE_DIR}/tests/relocatable.pure"
      TIMEOUT 35
  )
  add_test(
    NAME pure-tk-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_PREFIX=${PURE_PREFIX}"
      "-DMODULE_FILE=$<TARGET_FILE:pure-tk>"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DTCL_PREFIX=${TCL_PREFIX}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DEXPECTED_MARKER=PURE_TK_SMOKE_OK"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/smoke-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunRelocatableTest.cmake"
  )
  set_tests_properties(
    pure-tk-smoke
    PROPERTIES
      LABELS "tk;widget;callback;event;shutdown;sanitized"
      REQUIRED_FILES
        "$<TARGET_FILE:pure-tk>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 35
  )
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
