cmake_minimum_required(VERSION 3.25)

project(pure-gsl VERSION 0.12 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GSL REQUIRED IMPORTED_TARGET "gsl>=2.8")
pkg_get_variable(GSL_PREFIX gsl prefix)
if(WIN32)
  set(GSL_RUNTIME_DIR "${GSL_PREFIX}/bin")
else()
  pkg_get_variable(GSL_RUNTIME_DIR gsl libdir)
endif()

add_library(gsl MODULE gsl.c)
target_compile_features(gsl PRIVATE c_std_11)
target_link_libraries(gsl PRIVATE PkgConfig::PURE PkgConfig::GSL)
if(MINGW)
  target_link_options(gsl PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(
  gsl
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

if(WIN32)
  find_file(
    GSL_RUNTIME_DLL
    NAMES libgsl-28.dll
    HINTS "${GSL_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  find_file(
    GSLCBLAS_RUNTIME_DLL
    NAMES libgslcblas-0.dll
    HINTS "${GSL_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
    "llvm-readobj used for Windows PE validation")
  if(NOT LLVM_READOBJ_EXECUTABLE OR NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "Windows validation requires an existing LLVM_READOBJ_EXECUTABLE")
  endif()
  add_custom_target(
    verify-windows-dependencies
    COMMAND "${CMAKE_COMMAND}"
      "-DLLVM_READOBJ=${LLVM_READOBJ_EXECUTABLE}"
      "-DGSL_MODULE=$<TARGET_FILE:gsl>"
      "-DGSL_DLL=${GSL_RUNTIME_DLL}"
      "-DGSLCBLAS_DLL=${GSLCBLAS_RUNTIME_DLL}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/VerifyWindowsDependencies.cmake"
    DEPENDS gsl
    COMMENT "Verifying the pure-gsl Windows dependency closure"
    VERBATIM
  )
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  if(WIN32)
    set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter for tests")
    if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "BUILD_TESTING requires an existing PURE_EXECUTABLE")
    endif()
  else()
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  endif()
  add_test(
    NAME pure-gsl-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPACKAGE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:gsl>"
      "-DRUNTIME_BIN_DIR=${GSL_RUNTIME_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/load.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-gsl-load
    PROPERTIES
      LABELS "gsl;load;modules"
      REQUIRED_FILES "$<TARGET_FILE:gsl>;${CMAKE_CURRENT_SOURCE_DIR}/gsl.pure"
      TIMEOUT 30
  )
  add_test(
    NAME pure-gsl-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPACKAGE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:gsl>"
      "-DRUNTIME_BIN_DIR=${GSL_RUNTIME_DIR}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunPureTest.cmake"
  )
  set_tests_properties(
    pure-gsl-smoke
    PROPERTIES
      LABELS "gsl;matrix;svd;statistics;polynomial-roots;fit;special-functions"
      REQUIRED_FILES
        "$<TARGET_FILE:gsl>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 60
  )
  if(WIN32)
    set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-gsl contract")
    add_test(NAME pure-gsl-runner-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/runner"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runner_contract.cmake")
    add_test(NAME pure-gsl-configure-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DTEST_ROOT=${contract_root}/configure"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DC_COMPILER=${CMAKE_C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    add_test(NAME pure-gsl-runtime-verifier-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DTEST_ROOT=${contract_root}/verifier"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/runtime_verifier_contract.cmake")
    add_test(NAME pure-gsl-install-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/install"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
      "-DGSL_RUNTIME_DLL=${GSL_RUNTIME_DLL}"
      "-DGSLCBLAS_RUNTIME_DLL=${GSLCBLAS_RUNTIME_DLL}"
      "-DGSL_MODULE=$<TARGET_FILE:gsl>"
      "-DGSL_RUNTIME_LICENSE=${GSL_RUNTIME_LICENSE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
    set_tests_properties(pure-gsl-runner-contract pure-gsl-configure-contract
      pure-gsl-runtime-verifier-contract pure-gsl-install-contract
      PROPERTIES LABELS "gsl;contract" TIMEOUT 60)
  endif()
endif()
