cmake_minimum_required(VERSION 3.25)

foreach(required IN ITEMS SOURCE_DIR BINARY_DIR PURE_EXECUTABLE TEST_ROOT)
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

set(fixture "${TEST_ROOT}/source")
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${fixture}/pure-stlvec")
file(COPY "${SOURCE_DIR}/stlbase.pure" DESTINATION "${fixture}")
file(COPY
  "${SOURCE_DIR}/pure-stlvec/stlvec.pure"
  "${SOURCE_DIR}/pure-stlvec/stlvec"
  "${SOURCE_DIR}/pure-stlvec/ut"
  DESTINATION "${fixture}/pure-stlvec"
)
file(APPEND "${fixture}/pure-stlvec/ut/ut_minmax.pure"
  "\ntodo28_contract_invalid = @@@;\n")

execute_process(
  COMMAND "${CMAKE_COMMAND}"
    "-DPURE_EXECUTABLE=${PURE_EXECUTABLE}"
    "-DPACKAGE_DIRS=${fixture};${fixture}/pure-stlvec"
    "-DTEST_SOURCE_DIR=${fixture}"
    "-DMODULE_DIR=${BINARY_DIR}"
    -DTEST_KIND=stlvec
    -P "${SOURCE_DIR}/cmake/RunPackageTests.cmake"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)
if(result EQUAL 0)
  message(FATAL_ERROR
    "The package runner accepted a parser diagnostic:\n${output}${error}")
endif()
if(NOT "${output}\n${error}" MATCHES "emitted unexpected stderr")
  message(FATAL_ERROR
    "The runner rejected the parser fixture for the wrong reason:\n"
    "${output}${error}")
endif()
