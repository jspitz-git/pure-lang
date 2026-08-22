cmake_minimum_required(VERSION 3.25)

project(pure-rational VERSION 0.1 LANGUAGES NONE)

include(CTest)

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
configure_file(README "${CMAKE_CURRENT_BINARY_DIR}/README" @ONLY NEWLINE_STYLE UNIX)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
if(BUILD_TESTING)
  if(NOT PURE_EXECUTABLE OR NOT EXISTS "${PURE_EXECUTABLE}")
    message(FATAL_ERROR
      "BUILD_TESTING requires an existing PURE_EXECUTABLE: ${PURE_EXECUTABLE}")
  endif()

  set(contract_root "${CMAKE_CURRENT_BINARY_DIR}/pure-rational contract")
  add_test(
    NAME pure-rational-configure-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DTEST_ROOT=${contract_root}/configure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/configure_contract.cmake"
  )
  add_test(
    NAME pure-rational-install-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DTEST_ROOT=${contract_root}/install"
      "-DSMOKE_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/install_contract.cmake"
  )
  set_tests_properties(
    pure-rational-install-contract
    PROPERTIES
      ENVIRONMENT "PURELIB=${contract_root}/install/poison PURELIB"
  )
endif()

install(
  FILES rational.pure rat_interval.pure
  DESTINATION "${PURE_LIBRARY_INSTALL_DIR}"
  COMPONENT runtime
)
install(
  FILES "${CMAKE_CURRENT_BINARY_DIR}/README" COPYING
  DESTINATION "${PURE_DOCUMENTATION_INSTALL_DIR}"
  COMPONENT documentation
)
