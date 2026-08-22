cmake_minimum_required(VERSION 3.25)

project(pure-sql3 VERSION 0.5 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(SQLITE3 REQUIRED IMPORTED_TARGET "sqlite3>=3.40")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(sql3util MODULE sql3util.c)
target_compile_features(sql3util PRIVATE c_std_99)
target_link_libraries(
  sql3util
  PRIVATE
    PkgConfig::PURE
    PkgConfig::SQLITE3
    PkgConfig::GMP
)
set_target_properties(
  sql3util
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  if(WIN32)
    set(PURE_EXECUTABLE "" CACHE FILEPATH "Installed Pure interpreter for tests")
    set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH "llvm-readobj for PE tests")
    if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "BUILD_TESTING requires an existing PURE_EXECUTABLE")
    endif()
    if(NOT LLVM_READOBJ_EXECUTABLE OR
        NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
      message(FATAL_ERROR
        "BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE")
    endif()
  else()
    find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  endif()
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
  if(NOT EXISTS "${pure_runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()
  get_filename_component(sqlite_runtime_dir "${PURE_SQLITE_RUNTIME_DLL}" DIRECTORY)
  add_test(
    NAME pure-sql3-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DMODULE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DLL_DIR=$<TARGET_FILE_DIR:sql3util>"
      "-DSQLITE_RUNTIME_DIR=${sqlite_runtime_dir}"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/smoke-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set(sql3_tests pure-sql3-smoke)
  if(WIN32)
    set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-sql3 contract")
    add_test(NAME pure-sql3-configure-contract COMMAND "${CMAKE_COMMAND}"
    "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
    "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    "-DTEST_ROOT=${contract_root}/configure"
    "-DGENERATOR=${CMAKE_GENERATOR}"
    "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
    "-DC_COMPILER=${CMAKE_C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
    "-DPKG_CONFIG_PATH=${pure_runtime_prefix}/lib/pkgconfig;${SQLITE3_PREFIX}/lib/pkgconfig"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DSQLITE_RUNTIME_LICENSE=${PURE_SQLITE_RUNTIME_LICENSE}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    add_test(NAME pure-sql3-install-contract COMMAND "${CMAKE_COMMAND}"
    "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
    "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    "-DSQL3_TARGET_FILE=$<TARGET_FILE:sql3util>"
    "-DSQLITE_RUNTIME_DLL=${PURE_SQLITE_RUNTIME_DLL}"
    "-DSQLITE_RUNTIME_LICENSE=${PURE_SQLITE_RUNTIME_LICENSE}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
    "-DTEST_ROOT=${contract_root}/install"
    "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
    list(APPEND sql3_tests pure-sql3-configure-contract
      pure-sql3-install-contract)
  endif()
  set_tests_properties(${sql3_tests} PROPERTIES TIMEOUT 60 LABELS "pure-sql3")
endif()
