cmake_minimum_required(VERSION 3.25)

project(pure-sockets VERSION 0.8 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

add_library(sockets MODULE sockets.c)
target_link_libraries(sockets PRIVATE PkgConfig::PURE)
if(WIN32)
  target_link_libraries(sockets PRIVATE ws2_32)
endif()
set_target_properties(
  sockets
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

set(
  PURE_LIBRARY_INSTALL_DIR "lib/pure"
  CACHE STRING "Relative install directory for Pure modules"
)
set(
  PURE_DOCUMENTATION_INSTALL_DIR "share/doc/${PROJECT_NAME}"
  CACHE STRING "Relative install directory for package documentation"
)
set(
  PURE_EXAMPLES_INSTALL_DIR "${PURE_DOCUMENTATION_INSTALL_DIR}/examples"
  CACHE STRING "Relative install directory for package examples"
)
foreach(destination_var IN ITEMS
    PURE_LIBRARY_INSTALL_DIR
    PURE_DOCUMENTATION_INSTALL_DIR
    PURE_EXAMPLES_INSTALL_DIR)
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
  "${CMAKE_CURRENT_BINARY_DIR}/README"
  @ONLY
  NEWLINE_STYLE UNIX
)
file(READ "${CMAKE_CURRENT_BINARY_DIR}/README" readme)
string(REPLACE "|today|" "${today}" readme "${readme}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/README" "${readme}")

install(
  TARGETS sockets
  RUNTIME DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  LIBRARY DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES sockets.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_BINARY_DIR}/README" COPYING COPYING.LESSER
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
install(
  DIRECTORY examples/
  DESTINATION "${PURE_EXAMPLES_INSTALL_DIR}"
  COMPONENT documentation
  FILES_MATCHING PATTERN "*.pure"
)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
set(
  LLVM_READOBJ_EXECUTABLE ""
  CACHE FILEPATH "llvm-readobj used to verify the Windows package"
)

if(BUILD_TESTING AND WIN32)
  if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
    message(FATAL_ERROR
      "BUILD_TESTING requires an existing PURE_EXECUTABLE")
  endif()
  if(NOT LLVM_READOBJ_EXECUTABLE OR
      NOT EXISTS "${LLVM_READOBJ_EXECUTABLE}")
    message(FATAL_ERROR
      "BUILD_TESTING requires an existing LLVM_READOBJ_EXECUTABLE")
  endif()
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(pure_runtime_prefix "${pure_bin_dir}" DIRECTORY)
  if(NOT EXISTS "${pure_runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()

  add_executable(winsock-audit tests/winsock-audit.c)
  target_compile_definitions(winsock-audit PRIVATE WIN32_LEAN_AND_MEAN)
  add_test(
    NAME pure-sockets-winsock-audit
    COMMAND "${CMAKE_COMMAND}"
      "-DAUDIT_EXECUTABLE=$<TARGET_FILE:winsock-audit>"
      "-DSOCKETS_DLL=$<TARGET_FILE:sockets>"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunNativeAudit.cmake"
  )
  set_tests_properties(
    pure-sockets-winsock-audit
    PROPERTIES
      LABELS "sockets;winsock;audit"
      REQUIRED_FILES "$<TARGET_FILE:sockets>"
      TIMEOUT 10
  )

  add_test(
    NAME pure-sockets-loopback
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:sockets>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set_tests_properties(
    pure-sockets-loopback
    PROPERTIES
      LABELS "sockets;tcp;udp;loopback;smoke"
      REQUIRED_FILES
        "$<TARGET_FILE:sockets>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 30
  )

  set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-sockets contract")
  add_test(NAME pure-sockets-configure-contract COMMAND "${CMAKE_COMMAND}"
    "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
    "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    "-DTEST_ROOT=${contract_root}/configure"
    "-DGENERATOR=${CMAKE_GENERATOR}"
    "-DMAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
    "-DC_COMPILER=${CMAKE_C_COMPILER}"
    "-DPKG_CONFIG_EXECUTABLE=${PKG_CONFIG_EXECUTABLE}"
    "-DPURE_PKG_CONFIG_PATH=${pure_runtime_prefix}/lib/pkgconfig"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake")
  set_tests_properties(pure-sockets-configure-contract PROPERTIES
    LABELS "sockets;contract")
  add_test(NAME pure-sockets-install-contract COMMAND "${CMAKE_COMMAND}"
    "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
    "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
    "-DSOCKETS_TARGET_FILE=$<TARGET_FILE:sockets>"
    "-DAUDIT_EXECUTABLE=$<TARGET_FILE:winsock-audit>"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DLLVM_READOBJ_EXECUTABLE=${LLVM_READOBJ_EXECUTABLE}"
    "-DTEST_ROOT=${contract_root}/install"
    "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake")
  set_tests_properties(pure-sockets-install-contract PROPERTIES
    LABELS "sockets;contract;install;pe" TIMEOUT 60)
endif()
