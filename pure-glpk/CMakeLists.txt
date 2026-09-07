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
get_filename_component(GLPK_RUNTIME_DIR "${GLPK_LIBRARY}" DIRECTORY)

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
  get_filename_component(GLPK_RUNTIME_DIR "${GLPK_RUNTIME_DLL}" DIRECTORY)
  set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
    "llvm-readobj used for Windows PE validation")
  if(NOT LLVM_READOBJ_EXECUTABLE OR
      NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}" OR
      IS_DIRECTORY "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "Windows validation requires an existing LLVM_READOBJ_EXECUTABLE")
  endif()
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
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
  if(WIN32)
    set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter for tests")
    if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}" OR
        IS_DIRECTORY "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "BUILD_TESTING requires an existing PURE_EXECUTABLE")
    endif()
  else()
    find_program(
      PURE_EXECUTABLE
      NAMES pure
      HINTS "${PURE_PREFIX}/bin"
      NO_DEFAULT_PATH
      REQUIRED
    )
  endif()
  add_test(
    NAME pure-glpk-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPACKAGE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:glpk>"
      "-DRUNTIME_BIN_DIR=${GLPK_RUNTIME_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
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
      "-DPACKAGE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:glpk>"
      "-DRUNTIME_BIN_DIR=${GLPK_RUNTIME_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-glpk-smoke
    PROPERTIES
      LABELS "glpk;lp;mip;errors;cleanup"
      REQUIRED_FILES "$<TARGET_FILE:glpk>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 60
  )
  if(WIN32)
    set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-glpk-contract")
    find_program(PURE_GLPK_MAKE_EXECUTABLE NAMES make REQUIRED)
    add_test(
      NAME pure-glpk-runner-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DTEST_ROOT=${contract_root}/runner"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_contract.cmake"
    )
    add_test(
      NAME pure-glpk-configure-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DTEST_ROOT=${contract_root}/configure"
        "-DGENERATOR=${CMAKE_GENERATOR}"
        "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
        "-DC_COMPILER=${CMAKE_C_COMPILER}"
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake"
    )
    add_test(
      NAME pure-glpk-source-dist-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DCONTRACT_ROOT=${contract_root}"
        "-DTEST_ROOT=${contract_root}/source-dist"
        "-DMAKE_EXECUTABLE=${PURE_GLPK_MAKE_EXECUTABLE}"
        "-DGENERATOR=${CMAKE_GENERATOR}"
        "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
        "-DC_COMPILER=${CMAKE_C_COMPILER}"
        "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
        "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
        "-DMSYSTEM_PREFIX=$ENV{MSYSTEM_PREFIX}"
        "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/source_dist_contract.cmake"
    )
    set_tests_properties(
      pure-glpk-runner-contract pure-glpk-configure-contract
      PROPERTIES LABELS "glpk;contract" TIMEOUT 60
    )
    set_tests_properties(
      pure-glpk-source-dist-contract
      PROPERTIES LABELS "glpk;contract;dist" TIMEOUT 180
    )
  endif()
endif()
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

if(BUILD_TESTING AND WIN32)
  add_test(
    NAME pure-glpk-runtime-verifier-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DCONTRACT_ROOT=${contract_root}"
      "-DPORTABLE_PURE_PREFIX=${PURE_PREFIX}"
      "-DTEST_ROOT=${contract_root}/runtime verifier"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_verifier_contract.cmake"
  )
  add_test(
    NAME pure-glpk-install-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DCONTRACT_ROOT=${contract_root}"
      "-DTEST_ROOT=${contract_root}/install"
      "-DPORTABLE_PURE_PREFIX=${PURE_PREFIX}"
      "-DSOURCE_RUNTIME_DIR=${GLPK_RUNTIME_DIR}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
      "-DGLPK_MODULE_SOURCE=$<TARGET_FILE:glpk>"
      "-DGLPK_INTERFACE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/glpk.pure"
      "-DREADME_SOURCE=${CMAKE_CURRENT_BINARY_DIR}/README"
      "-DCOPYING_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/COPYING"
      "-DWINDOWS_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/WINDOWS.md"
      "-DEXAMPLE_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/examples/lp.pure"
      "-DTEST_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DGLPK_DLL_SOURCE=${GLPK_RUNTIME_DLL}"
      "-DCOLAMD_DLL_SOURCE=${COLAMD_RUNTIME_DLL}"
      "-DAMD_DLL_SOURCE=${AMD_RUNTIME_DLL}"
      "-DSUITESPARSECONFIG_DLL_SOURCE=${SUITESPARSECONFIG_RUNTIME_DLL}"
      "-DOMP_DLL_SOURCE=${OMP_RUNTIME_DLL}"
      "-DGLPK_LICENSE_SOURCE=${GLPK_RUNTIME_LICENSE}"
      "-DSUITESPARSE_LICENSE_SOURCE=${SUITESPARSE_RUNTIME_LICENSE}"
      "-DOPENMP_LICENSE_SOURCE=${OPENMP_RUNTIME_LICENSE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake"
  )
  set_tests_properties(
    pure-glpk-runtime-verifier-contract pure-glpk-install-contract
    PROPERTIES
      LABELS "glpk;contract"
      REQUIRED_FILES "$<TARGET_FILE:glpk>"
      TIMEOUT 300
  )
endif()
