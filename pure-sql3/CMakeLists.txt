cmake_minimum_required(VERSION 3.25)

project(pure-sql3 VERSION 0.5 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(SQLITE3 REQUIRED IMPORTED_TARGET "sqlite3>=3.40")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(sql3util MODULE sql3util.c)
target_compile_features(sql3util PRIVATE c_std_99)
target_link_libraries(
  sql3util
  PRIVATE
    PkgConfig::PURE
    PkgConfig::SQLITE3
    PkgConfig::GMP
)
set_target_properties(
  sql3util
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
