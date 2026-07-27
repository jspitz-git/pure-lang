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

if(BUILD_TESTING AND WIN32)
  add_executable(winsock-audit tests/winsock-audit.c)
  target_compile_definitions(winsock-audit PRIVATE WIN32_LEAN_AND_MEAN)
  add_test(
    NAME pure-sockets-winsock-audit
    COMMAND "$<TARGET_FILE:winsock-audit>" "$<TARGET_FILE:sockets>"
  )
  set_tests_properties(
    pure-sockets-winsock-audit
    PROPERTIES
      LABELS "sockets;winsock;audit"
      REQUIRED_FILES "$<TARGET_FILE:sockets>"
      TIMEOUT 10
  )

  if(PURE_EXECUTABLE)
    if(NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "PURE_EXECUTABLE does not exist: ${PURE_EXECUTABLE}")
    endif()
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
  else()
    message(STATUS
      "PURE_EXECUTABLE is not set; pure-sockets loopback test is disabled")
  endif()
endif()
