cmake_minimum_required(VERSION 3.25)

project(pure-glpk VERSION 0.6 LANGUAGES C)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
pkg_check_modules(GMP REQUIRED IMPORTED_TARGET gmp)

find_path(
  GLPK_INCLUDE_DIR
  NAMES glpk.h
  HINTS "$ENV{MSYSTEM_PREFIX}/include"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  GLPK_LIBRARY
  NAMES glpk
  HINTS "$ENV{MSYSTEM_PREFIX}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)

add_library(glpk MODULE glpk.c)
target_compile_features(glpk PRIVATE c_std_11)
target_include_directories(glpk PRIVATE "${GLPK_INCLUDE_DIR}")
target_link_libraries(
  glpk
  PRIVATE
    PkgConfig::PURE
    PkgConfig::GMP
    "${GLPK_LIBRARY}"
)
if(WIN32)
  target_link_libraries(glpk PRIVATE odbc32)
endif()
if(MINGW)
  target_link_options(glpk PRIVATE "LINKER:--enable-auto-import")
endif()
set_target_properties(
  glpk
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(
    PURE_EXECUTABLE
    NAMES pure
    HINTS "${PURE_PREFIX}/bin"
    NO_DEFAULT_PATH
    REQUIRED
  )
  add_test(
    NAME pure-glpk-load
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:glpk>"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunLoadTest.cmake"
  )
  set_tests_properties(
    pure-glpk-load
    PROPERTIES
      LABELS "glpk;load"
      REQUIRED_FILES "$<TARGET_FILE:glpk>;${CMAKE_CURRENT_SOURCE_DIR}/glpk.pure"
      TIMEOUT 30
  )
endif()
