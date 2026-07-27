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
