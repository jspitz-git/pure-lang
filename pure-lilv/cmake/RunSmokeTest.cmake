foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR PURE_RUNTIME_DIR
    LILV_RUNTIME_DIR DEPENDENCY_RUNTIME_DIR EMPTY_LV2_ROOT TEST_LV2_ROOT
    PRESET_ROOT TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${PRESET_ROOT}/saved-state.lv2")
unset(ENV{PURELIB})
unset(ENV{LV2_PATH})
set(ENV{PATH}
  "${MODULE_DIR};${LILV_RUNTIME_DIR};${DEPENDENCY_RUNTIME_DIR};${PURE_RUNTIME_DIR};C:/Windows/System32;C:/Windows")

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
    "${EMPTY_LV2_ROOT}"
    "${TEST_LV2_ROOT}"
    "${PRESET_ROOT}"
  WORKING_DIRECTORY "${PRESET_ROOT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 50
  ENCODING UTF-8)

if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR
    "pure-lilv smoke test exited with ${result}\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_LILV_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-lilv smoke test did not emit its success marker\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT EXISTS "${PRESET_ROOT}/saved-state.lv2/manifest.ttl")
  message(FATAL_ERROR "pure-lilv did not save the controlled preset bundle")
endif()

message(STATUS "pure-lilv smoke test passed")
