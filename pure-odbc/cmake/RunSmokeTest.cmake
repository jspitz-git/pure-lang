foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_DIRECTORY}")
file(MAKE_DIRECTORY "${TEST_DIRECTORY}")
file(COPY
  "${PURE_SOURCE_DIR}/tests/data/people.csv"
  "${PURE_SOURCE_DIR}/tests/data/Schema.ini"
  DESTINATION "${TEST_DIRECTORY}"
)
file(TO_CMAKE_PATH "${TEST_DIRECTORY}" test_directory)

set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
set(ENV{PURE_ODBC_TEST_DIRECTORY} "${test_directory}")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${PURE_SOURCE_DIR}/tests/smoke.pure"
  WORKING_DIRECTORY "${TEST_DIRECTORY}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-odbc smoke test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "pure-odbc manager/diagnostic/CSV smoke test passed")
