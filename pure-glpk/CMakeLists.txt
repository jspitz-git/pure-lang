cmake_minimum_required(VERSION 3.25)

project(pure-glpk VERSION 0.6 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

find_path(
  GLPK_INCLUDE_DIR
  NAMES glpk.h
  HINTS "$ENV{MSYSTEM_PREFIX}/include"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  GLPK_LIBRARY
  NAMES glpk
  HINTS "$ENV{MSYSTEM_PREFIX}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)

add_library(glpk MODULE glpk.c)
target_compile_features(glpk PRIVATE c_std_11)
target_include_directories(glpk PRIVATE "${GLPK_INCLUDE_DIR}")
target_link_libraries(
  glpk
  PRIVATE
    PkgConfig::PURE
    PkgConfig::GMP
    "${GLPK_LIBRARY}"
)
if(WIN32)
  target_link_libraries(glpk PRIVATE odbc32)
endif()
if(MINGW)
  target_link_options(glpk PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(
  glpk
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

if(WIN32)
  foreach(runtime IN ITEMS
      GLPK:libglpk-40.dll
      COLAMD:libcolamd.dll
      AMD:libamd.dll
      SUITESPARSECONFIG:libsuitesparseconfig.dll
      OMP:libomp.dll
      GMP:libgmp-10.dll
      ZLIB:zlib1.dll)
    string(REPLACE ":" ";" runtime_pair "${runtime}")
    list(GET runtime_pair 0 runtime_name)
    list(GET runtime_pair 1 runtime_file)
    find_file(
      "${runtime_name}_RUNTIME_DLL"
      NAMES "${runtime_file}"
      HINTS "$ENV{MSYSTEM_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
  endforeach()
  find_program(LLVM_READOBJ NAMES llvm-readobj REQUIRED)
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ}"
      "-DGLPK_MODULE=$<TARGET_FILE:glpk>"
      "-DGLPK_DLL=${GLPK_RUNTIME_DLL}"
      "-DCOLAMD_DLL=${COLAMD_RUNTIME_DLL}"
      "-DAMD_DLL=${AMD_RUNTIME_DLL}"
      "-DSUITESPARSECONFIG_DLL=${SUITESPARSECONFIG_RUNTIME_DLL}"
      "-DOMP_DLL=${OMP_RUNTIME_DLL}"
      "-DGMP_DLL=${GMP_RUNTIME_DLL}"
      "-DZLIB_DLL=${ZLIB_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS glpk
    COMMENT "Verifying the pure-glpk Windows dependency closure"
    VERBATIM
  )
endif()

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  add_test(
    NAME pure-glpk-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:glpk>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunLoadTest.cmake"
  )
  set_tests_properties(
    pure-glpk-load
    PROPERTIES
      LABELS "glpk;load"
      REQUIRED_FILES "$<TARGET_FILE:glpk>;${CMAKE_CURRENT_SOURCE_DIR}/glpk.pure"
      TIMEOUT 30
  )
  add_test(
    NAME pure-glpk-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:glpk>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set_tests_properties(
    pure-glpk-smoke
    PROPERTIES
      LABELS "glpk;lp;mip;errors;cleanup"
      REQUIRED_FILES "$<TARGET_FILE:glpk>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 60
  )
endif()
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")
