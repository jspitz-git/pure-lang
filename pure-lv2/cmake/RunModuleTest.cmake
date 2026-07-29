foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR PURE_RUNTIME_DIR TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

unset(ENV{PURELIB})
unset(ENV{LV2_PATH})
set(ENV{PATH}
  "${MODULE_DIR};${PURE_RUNTIME_DIR};C:/Windows/System32;C:/Windows")
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 20
  ENCODING UTF-8)
if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR
    "pure-lv2 module test exited with ${result}\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_LV2_MODULE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-lv2 module test did not emit its success marker\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()

message(STATUS "pure-lv2 module test passed")
