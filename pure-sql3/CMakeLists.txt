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

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/Install.cmake")

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  add_test(
    NAME pure-sql3-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DMODULE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DLL_DIR=$<TARGET_FILE_DIR:sql3util>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/smoke-test"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set_tests_properties(pure-sql3-smoke PROPERTIES TIMEOUT 60)
endif()
