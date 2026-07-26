cmake_minimum_required(VERSION 3.25)

project(pure-csv VERSION 1.6 LANGUAGES C)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")

add_library(csv MODULE csv.c)
target_link_libraries(csv PRIVATE PkgConfig::PURE)
set_target_properties(
  csv
  PROPERTIES
    PREFIX ""
    WINDOWS_EXPORT_ALL_SYMBOLS ON
)

set(
  PURE_EXECUTABLE ""
  CACHE FILEPATH "Pure interpreter used for package smoke tests"
)
if(BUILD_TESTING)
  if(PURE_EXECUTABLE)
    if(NOT EXISTS "${PURE_EXECUTABLE}")
      message(FATAL_ERROR "PURE_EXECUTABLE does not exist: ${PURE_EXECUTABLE}")
    endif()
    if(WIN32)
      set(PURE_CSV_NATIVE_NEWLINE "CRLF")
    else()
      set(PURE_CSV_NATIVE_NEWLINE "LF")
    endif()
    add_test(
      NAME pure-csv-smoke
      COMMAND "${CMAKE_COMMAND}"
        "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
        "-DPURE_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
        "-DPURE_MODULE_DIR=$<TARGET_FILE_DIR:csv>"
        "-DTEST_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.pure"
        "-DTEST_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}/pure csv smoke data"
        "-DNATIVE_NEWLINE=${PURE_CSV_NATIVE_NEWLINE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunSmokeTest.cmake"
    )
  else()
    message(STATUS "PURE_EXECUTABLE is not set; pure-csv smoke test is disabled")
  endif()
endif()
