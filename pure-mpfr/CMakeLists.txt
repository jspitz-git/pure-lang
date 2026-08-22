cmake_minimum_required(VERSION 3.25)

project(pure-mpfr VERSION 0.5 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(MPFR REQUIRED IMPORTED_TARGET "mpfr>=4.2")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(mpfr MODULE mpfr.c)
target_link_libraries(
  mpfr
  PRIVATE
    PkgConfig::PURE
    PkgConfig::MPFR
    PkgConfig::GMP
)
set_target_properties(
  mpfr
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

set(PURE_LIBRARY_INSTALL_DIR "lib/pure" CACHE STRING
  "Install directory for the Pure module and its shared library")
set(PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}" CACHE STRING
  "Install directory for pure-mpfr documentation")
set(PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples" CACHE STRING
  "Install directory for pure-mpfr examples")

foreach(install_dir IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR
    PURE_EXAMPLES_INSTALL_DIR)
  if(IS_ABSOLUTE "${${install_dir}}" OR "${${install_dir}}" MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${install_dir} must stay inside CMAKE_INSTALL_PREFIX: ${${install_dir}}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(README "${CMAKE_CURRENT_BINARY_DIR}/README" @ONLY NEWLINE_STYLE UNIX)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(TARGETS mpfr
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
)
install(FILES mpfr.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/README"
    COPYING
    COPYING.LESSER
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
)
install(DIRECTORY examples/
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  FILES_MATCHING PATTERN "*.pure"
)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
set(LLVM_READOBJ_EXECUTABLE "" CACHE FILEPATH
  "llvm-readobj used for the Windows package contract")
if(BUILD_TESTING)
  if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
    message(FATAL_ERROR
      "BUILD_TESTING requires an existing PURE_EXECUTABLE: ${PURE_EXECUTABLE}")
  endif()
  if(WIN32 AND NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "Windows BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE: "
      "${LLVM_READOBJ_EXECUTABLE}")
  endif()
    add_executable(mpfr-abi-probe tests/abi-probe.c)
    target_link_libraries(mpfr-abi-probe PRIVATE PkgConfig::MPFR PkgConfig::GMP)
    add_test(NAME pure-mpfr-configure-contract COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/pure-mpfr contract/configure"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DC_COMPILER=${CMAKE_C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DWINDOWS_BUILD=${WIN32}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
    add_test(
      NAME pure-mpfr-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:mpfr>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
    )
    add_test(NAME pure-mpfr-abi COMMAND "${CMAKE_COMMAND}"
      "-DABI_PROBE=$<TARGET_FILE:mpfr-abi-probe>"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/run_abi_probe.cmake")
    set(mpfr_tests pure-mpfr-configure-contract pure-mpfr-smoke pure-mpfr-abi)
    if(WIN32)
      add_test(NAME pure-mpfr-install-contract COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DMPFR_TARGET_FILE=$<TARGET_FILE:mpfr>"
        "-DABI_PROBE=$<TARGET_FILE:mpfr-abi-probe>"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
        "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/pure-mpfr contract/install"
        "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
      list(APPEND mpfr_tests pure-mpfr-install-contract)
    endif()
    set_tests_properties(
      ${mpfr_tests}
      PROPERTIES
        LABELS "pure-mpfr"
    )
endif()
