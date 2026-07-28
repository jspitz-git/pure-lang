foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT TEST_DIRECTORY)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_DIRECTORY}")
file(MAKE_DIRECTORY "${TEST_DIRECTORY}")
set(ENV{PATH} "${MODULE_DIR};$ENV{PATH}")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PURE_SOURCE_DIR}"
    -I "${PURE_SOURCE_DIR}/fftw"
    -I "${PURE_SOURCE_DIR}/samplerate"
    -I "${PURE_SOURCE_DIR}/sndfile"
    -I "${PURE_SOURCE_DIR}/realtime"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${TEST_DIRECTORY}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
file(REMOVE "${TEST_DIRECTORY}/pure-audio-smoke.wav")
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-audio test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "pure-audio hardware-free test passed")
