cmake_minimum_required(VERSION 3.25)

project(pure-tk VERSION 0.5 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_get_variable(TCL_PREFIX tcl prefix)

find_path(
  TCL_INCLUDE_DIR
  NAMES tcl.h tk.h
  HINTS "${TCL_PREFIX}/include"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  TCL_LIBRARY
  NAMES tcl86 tcl
  HINTS "${TCL_PREFIX}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  TK_LIBRARY
  NAMES tk86 tk
  HINTS "${TCL_PREFIX}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)

add_library(pure-tk MODULE tk.c)
target_compile_features(pure-tk PRIVATE c_std_11)
target_include_directories(pure-tk PRIVATE "${TCL_INCLUDE_DIR}")
target_compile_options(pure-tk PRIVATE -Wall -Wextra -Werror)
target_link_libraries(
  pure-tk
  PRIVATE
    PkgConfig::PURE
    "${TCL_LIBRARY}"
    "${TK_LIBRARY}"
)
set_target_properties(
  pure-tk
  PROPERTIES
    OUTPUT_NAME tk
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
