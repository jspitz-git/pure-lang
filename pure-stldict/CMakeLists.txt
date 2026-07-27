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

include(CTest)
if(BUILD_TESTING)
  pkg_get_variable(PURE_PREFIX pure prefix)
  find_program(PURE_EXECUTABLE NAMES pure HINTS "${PURE_PREFIX}/bin" REQUIRED)
  add_test(
    NAME pure-stldict-smoke
    COMMAND "${CMAKE_COMMAND}"
      "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
      "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DMODULE_DIR=$<TARGET_FILE_DIR:hashdict>"
      "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
  )
  set_tests_properties(
    pure-stldict-smoke
    PROPERTIES
      LABELS "stldict;hashdict;orddict;lifetime"
      REQUIRED_FILES
        "$<TARGET_FILE:hashdict>;$<TARGET_FILE:orddict>;${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
      TIMEOUT 60
  )
endif()
