cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

get_filename_component(binary_root "${BINARY_DIR}" ABSOLUTE)
get_filename_component(test_root "${TEST_ROOT}" ABSOLUTE)
cmake_path(IS_PREFIX binary_root "${test_root}" NORMALIZE safe_root)
if(NOT safe_root OR test_root STREQUAL binary_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BINARY_DIR")
endif()

set(fake_pure "${TEST_ROOT}/bin/pure.cmd")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}/bin" "${TEST_ROOT}/lib/pure")
file(WRITE "${TEST_ROOT}/lib/pure/math.pure" "fixture\n")
file(WRITE "${fake_pure}" "@echo off\r\n"
  "echo --- PASSED STLVEC UNIT TESTS ---\r\n"
  "echo libunwind: hidden parser diagnostic pc not in table, pc=0x123ABC 1>&2\r\n")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${fake_pure}"
    "-DPACKAGE_DIRS=${SOURCE_DIR}"
    "-DTEST_SOURCE_DIR=${SOURCE_DIR}"
    "-DMODULE_DIR=${BINARY_DIR}"
    -DTEST_KIND=stlvec
    -P "${SOURCE_DIR}/cmake/RunPackageTests.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)
if(result EQUAL 0)
  message(FATAL_ERROR
    "The runner allowlisted additional text on a libunwind line")
endif()
if(NOT "${output}\n${error}" MATCHES "emitted unexpected stderr")
  message(FATAL_ERROR
    "The runner rejected the allowlist fixture for the wrong reason:\n"
    "${output}${error}")
endif()
