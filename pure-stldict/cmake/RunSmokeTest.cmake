foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT)
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
    "pure-stldict smoke test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "PURE_STLDICT_SMOKE_OK")
  message(FATAL_ERROR
    "pure-stldict smoke marker missing\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
