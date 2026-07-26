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
  if(PURE_EXECUTABLE)
    if(NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "PURE_EXECUTABLE does not exist: ${PURE_EXECUTABLE}")
    endif()
    add_test(
      NAME pure-rational-smoke
      COMMAND "${PURE_EXECUTABLE}" --norc -x
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
    )
  else()
    message(STATUS
      "PURE_EXECUTABLE is not set; pure-rational smoke test is disabled")
  endif()
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