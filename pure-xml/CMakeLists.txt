cmake_minimum_required(VERSION 3.25)

project(pure-xml VERSION 0.7 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(LIBXML2 REQUIRED IMPORTED_TARGET "libxml-2.0>=2.9")
pkg_check_modules(LIBXSLT REQUIRED IMPORTED_TARGET "libxslt>=1.1")

add_library(xml MODULE xml.c)
target_compile_features(xml PRIVATE c_std_11)
target_link_libraries(
  xml
  PRIVATE
    PkgConfig::PURE
    PkgConfig::LIBXML2
    PkgConfig::LIBXSLT
)
if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(xml PRIVATE -Wno-deprecated-declarations)
elseif(MSVC)
  target_compile_options(xml PRIVATE /wd4996)
endif()
set_target_properties(
  xml
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)
