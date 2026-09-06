cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR PURE_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPACKAGE_DIRS=${SOURCE_DIR};${SOURCE_DIR}/pure-stlvec;${SOURCE_DIR}/pure-stlmap"
    "-DTEST_SOURCE_DIR=${SOURCE_DIR}"
    "-DMODULE_DIR=${BINARY_DIR}"
    -DTEST_KIND=stlvec
    -P "${SOURCE_DIR}/cmake/RunPackageTests.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "The stlvec suite failed:\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\n)--- TEST SUITE SV_NUMERIC ---([\r\n]|$)")
  message(FATAL_ERROR
    "The aggregate stlvec test did not execute SV_NUMERIC:\n${output}")
endif()
