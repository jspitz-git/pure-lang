foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR MODE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
if(NOT MODE STREQUAL "playback" AND NOT MODE STREQUAL "capture")
  message(FATAL_ERROR "MODE must be playback or capture")
endif()

set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -I "${PURE_SOURCE_DIR}/tests"
    -L "${MODULE_DIR}"
    -x "${PURE_SOURCE_DIR}/tests/hardware-${MODE}.pure"
  WORKING_DIRECTORY "${MODULE_DIR}"
  TIMEOUT 15
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-audio ${MODE} test failed or timed out (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
string(STRIP "${output}" output)
message(STATUS "${output}")
