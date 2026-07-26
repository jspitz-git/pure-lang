cmake_minimum_required(VERSION 3.25)

project(pure-csv VERSION 1.6 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

add_library(csv MODULE csv.c)
target_link_libraries(csv PRIVATE PkgConfig::PURE)
set_target_properties(
  csv
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
