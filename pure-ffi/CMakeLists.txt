cmake_minimum_required(VERSION 3.25)

project(pure-ffi VERSION 0.16 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LIBFFI REQUIRED IMPORTED_TARGET "libffi>=3.4")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(ffi MODULE ffi.c)
target_link_libraries(
  ffi
  PRIVATE
    PkgConfig::PURE
    PkgConfig::LIBFFI
    PkgConfig::GMP
)
if(MINGW)
  target_link_options(ffi PRIVATE LINKER:--enable-auto-import)
endif()
set_target_properties(
  ffi
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
