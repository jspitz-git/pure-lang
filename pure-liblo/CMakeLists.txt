cmake_minimum_required(VERSION 3.25)

project(pure-liblo VERSION 0.9 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/LibloDependency.cmake")

add_library(pure-liblo MODULE lo.c lo-add.c)
target_compile_features(pure-liblo PRIVATE c_std_11)
target_compile_definitions(pure-liblo PRIVATE HAVE_TIMETAG=1)
target_compile_options(pure-liblo PRIVATE
  -Wall
  -Wextra
  -Werror
  -Wno-unused-function)
target_link_libraries(pure-liblo PRIVATE
  liblo::liblo
  PkgConfig::PURE
  PkgConfig::GMP
  ws2_32)
add_dependencies(pure-liblo liblo-external)
set_target_properties(pure-liblo PROPERTIES
  OUTPUT_NAME lo
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(WIN32)
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DPURE_LIBLO_MODULE=$<TARGET_FILE:pure-liblo>"
      "-DLIBLO_DLL=${LIBLO_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS pure-liblo liblo-external
    COMMENT "Verifying the pure-liblo Windows dependency closure"
    VERBATIM
  )
endif()
include(CTest)
if(BUILD_TESTING AND WIN32)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  add_test(
    NAME pure-liblo-loopback
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:pure-liblo>"
      "-DLIBLO_RUNTIME_DIR=${LIBLO_PREFIX}/bin"
      "-DPURE_RUNTIME_DIR=${PURE_PREFIX}/bin"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/loopback.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-liblo-loopback
    PROPERTIES
      LABELS "liblo;osc;udp;loopback;message;bundle;callback;error;shutdown"
      REQUIRED_FILES
        "$<TARGET_FILE:pure-liblo>;${LIBLO_RUNTIME_DLL};${CMAKE_CURRENT_SOURCE_DIR}/tests/loopback.pure"
      TIMEOUT 30
  )
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
