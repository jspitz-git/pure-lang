cmake_minimum_required(VERSION 3.25)

project(pure-mpfr VERSION 0.5 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(MPFR REQUIRED IMPORTED_TARGET "mpfr>=4.2")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(mpfr MODULE mpfr.c)
target_link_libraries(
  mpfr
  PRIVATE
    PkgConfig::PURE
    PkgConfig::MPFR
    PkgConfig::GMP
)
set_target_properties(
  mpfr
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
