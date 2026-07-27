cmake_minimum_required(VERSION 3.25)

project(pure-stllib VERSION 0.6 LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

add_library(stlbase SHARED stlbase.cpp)
target_compile_features(stlbase PRIVATE cxx_std_17)
target_include_directories(stlbase PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(stlbase PRIVATE PkgConfig::PURE PkgConfig::GMP)

add_library(stlvec SHARED pure-stlvec/stlvec.cpp)
target_compile_features(stlvec PRIVATE cxx_std_17)
target_include_directories(
  stlvec
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec"
)
target_link_libraries(stlvec PRIVATE PkgConfig::PURE stlbase)

add_library(
  stlalgorithm
  SHARED
  pure-stlvec/sv_modifying.cpp
  pure-stlvec/sv_nonmodifying.cpp
  pure-stlvec/sv_sort.cpp
  pure-stlvec/sv_merge.cpp
  pure-stlvec/sv_heap.cpp
  pure-stlvec/sv_minmax.cpp
  pure-stlvec/sv_numeric.cpp
)
target_compile_features(stlalgorithm PRIVATE cxx_std_17)
target_include_directories(
  stlalgorithm
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlvec"
)
target_link_libraries(stlalgorithm PRIVATE PkgConfig::PURE stlbase stlvec)

foreach(module IN ITEMS stlmap stlmmap stlhmap)
  add_library(${module} SHARED "pure-stlmap/${module}.cpp")
  target_compile_features(${module} PRIVATE cxx_std_17)
  target_include_directories(
    ${module}
    PRIVATE
      "${CMAKE_CURRENT_SOURCE_DIR}"
      "${CMAKE_CURRENT_SOURCE_DIR}/pure-stlmap"
  )
  target_link_libraries(${module} PRIVATE PkgConfig::PURE stlbase)
endforeach()

foreach(module IN ITEMS
    stlbase
    stlvec
    stlalgorithm
    stlmap
    stlmmap
    stlhmap)
  set_target_properties(
    ${module}
    PROPERTIES
      CXX_EXTENSIONS OFF
      PREFIX ""
      WINDOWS_EXPORT_ALL_SYMBOLS ON
  )
endforeach()
