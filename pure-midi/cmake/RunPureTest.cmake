foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT TEST_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_DIRECTORY}")
file(MAKE_DIRECTORY "${TEST_DIRECTORY}")
if(DEFINED FIXTURE AND NOT "${FIXTURE}" STREQUAL "")
  file(COPY "${FIXTURE}" DESTINATION "${TEST_DIRECTORY}")
endif()
set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -I "${PURE_SOURCE_DIR}/midifile"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${TEST_DIRECTORY}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 45
  ENCODING UTF-8)
file(REMOVE "${TEST_DIRECTORY}/pure-midi-smoke.mid")
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-midi test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "pure-midi hardware-free test passed")
