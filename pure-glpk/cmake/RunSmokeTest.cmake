foreach(required IN ITEMS PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${MODULE_DIR}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-glpk solver smoke test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "pure-glpk LP/MIP/error/cleanup smoke test passed")
