cmake_minimum_required(VERSION 3.25)

project(pure-stldict VERSION 0.8 LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

foreach(module IN ITEMS hashdict orddict)
  add_library(${module} MODULE "${module}.cc")
  target_compile_features(${module} PRIVATE cxx_std_17)
  target_link_libraries(${module} PRIVATE PkgConfig::PURE)
  set_target_properties(
    ${module}
    PROPERTIES
      PREFIX ""
      WINDOWS_EXPORT_ALL_SYMBOLS ON
  )
endforeach()
