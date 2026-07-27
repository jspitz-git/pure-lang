foreach(required IN ITEMS
    PURE_EXECUTABLE MODULE_DIR MODULE_DLL_DIR TEST_SCRIPT TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}/database with spaces žluťoučký")

set(ENV{PATH} "${MODULE_DLL_DIR};$ENV{PATH}")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -I "${MODULE_DIR}" -x "${TEST_SCRIPT}" "${TEST_ROOT}"
  WORKING_DIRECTORY "${TEST_ROOT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

file(REMOVE_RECURSE "${TEST_ROOT}")

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-sql3 smoke test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "PURE_SQL3_SMOKE_OK")
  message(FATAL_ERROR "pure-sql3 smoke test did not emit its success marker")
endif()
message(STATUS "${output}")
