cmake_minimum_required(VERSION 3.25)

project(pure-sockets VERSION 0.8 LANGUAGES C)

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
