cmake_minimum_required(VERSION 3.25)

project(pure-csv VERSION 1.6 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}"
  CACHE STRING "Relative install directory for package documentation"
)
foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR)
  set(destination "${${destination_var}}")
  if(IS_ABSOLUTE "${destination}" OR
      destination MATCHES "(^|[/\\\\])\\.\\.([/\\\\]|$)")
    message(FATAL_ERROR
      "${destination_var} must remain within the installation prefix: ${destination}")
  endif()
endforeach()

set(version "${PROJECT_VERSION}")
string(TIMESTAMP today "%B %d, %Y")
configure_file(
  README
  "${CMAKE_CURRENT_BINARY_DIR}/README.configured"
  @ONLY
  NEWLINE_STYLE UNIX
)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README.configured" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

add_library(csv MODULE csv.c)
target_link_libraries(csv PRIVATE PkgConfig::PURE)
set_target_properties(
  csv
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
set(
  LLVM_READOBJ_EXECUTABLE ""
  CACHE FILEPATH "llvm-readobj used for the Windows package contract"
)
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
  if(WIN32)
    set(PURE_CSV_NATIVE_NEWLINE "CRLF")
  else()
    set(PURE_CSV_NATIVE_NEWLINE "LF")
  endif()

  set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-csv contract")
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
  add_test(
    NAME pure-csv-configure-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/configure"
      "-DGENERATOR=${CMAKE_GENERATOR}"
      "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
      "-DC_COMPILER=${CMAKE_C_COMPILER}"
      "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
      "-DPURE_PKG_CONFIG_PATH=${pure_runtime_prefix}/lib/pkgconfig"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake"
  )
  add_test(
    NAME pure-csv-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:csv>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DTEST_DIRECTORY=${contract_root}/build-tree smoke data"
      "-DNATIVE_NEWLINE=${PURE_CSV_NATIVE_NEWLINE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set(csv_tests pure-csv-configure-contract pure-csv-smoke)
  if(WIN32)
    add_test(
      NAME pure-csv-install-contract
      COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DCSV_TARGET_FILE=$<TARGET_FILE:csv>"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
        "-DTEST_ROOT=${contract_root}/install"
        "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        "-DNATIVE_NEWLINE=${PURE_CSV_NATIVE_NEWLINE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake"
    )
    list(APPEND csv_tests pure-csv-install-contract)
  endif()
  set_tests_properties(${csv_tests} PROPERTIES LABELS pure-csv)
endif()
install(
  TARGETS csv
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES csv.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_BINARY_DIR}/README" COPYING
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
