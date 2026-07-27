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
  )
endif()
