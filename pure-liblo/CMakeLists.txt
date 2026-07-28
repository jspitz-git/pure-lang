cmake_minimum_required(VERSION 3.25)

project(pure-liblo VERSION 0.9 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/LibloDependency.cmake")

add_library(pure-liblo MODULE lo.c lo-add.c)
target_compile_features(pure-liblo PRIVATE c_std_11)
target_compile_definitions(pure-liblo PRIVATE HAVE_TIMETAG=1)
target_compile_options(pure-liblo PRIVATE
  -Wall
  -Wextra
  -Werror
  -Wno-unused-function)
target_link_libraries(pure-liblo PRIVATE
  liblo::liblo
  PkgConfig::PURE
  PkgConfig::GMP
  ws2_32)
add_dependencies(pure-liblo liblo-external)
set_target_properties(pure-liblo PROPERTIES
  OUTPUT_NAME lo
  PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
