cmake_minimum_required(VERSION 3.25)
project(pure_fastcgi C)

if(NOT WIN32)
  message(FATAL_ERROR "pure-fastcgi requires Windows")
endif()

set(PURE_FASTCGI_FCGI2_ARCHIVE "" CACHE FILEPATH
  "Absolute path to the verified fcgi2 source archive")
if(NOT IS_ABSOLUTE "${PURE_FASTCGI_FCGI2_ARCHIVE}"
    OR NOT EXISTS "${PURE_FASTCGI_FCGI2_ARCHIVE}")
  message(FATAL_ERROR
    "PURE_FASTCGI_FCGI2_ARCHIVE must name an existing absolute file")
endif()

include(CTest)
if(BUILD_TESTING)
  add_test(
    NAME pure-fastcgi-source-contract
    COMMAND "${CMAKE_COMMAND}"
      "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
      "-DFCGI2_ARCHIVE=${PURE_FASTCGI_FCGI2_ARCHIVE}"
      "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/source-contract"
      -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/source-contract.cmake")
  set_tests_properties(pure-fastcgi-source-contract PROPERTIES
    LABELS "fastcgi;source;contract"
    TIMEOUT 30)
endif()
