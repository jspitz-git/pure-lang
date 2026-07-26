foreach(required_var IN ITEMS
    PURE_EXECUTABLE
    PURE_SOURCE_DIR
    PURE_MODULE_DIR
    TEST_SCRIPT
    TEST_DIRECTORY
    NATIVE_NEWLINE)
  if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
    message(FATAL_ERROR "${required_var} is required")
  endif()
endforeach()

file(MAKE_DIRECTORY "${TEST_DIRECTORY}")
set(ENV{PURE_CSV_TEST_DIRECTORY} "${TEST_DIRECTORY}")
set(ENV{PURE_CSV_NATIVE_NEWLINE} "${NATIVE_NEWLINE}")
unset(ENV{PURELIB})

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${PURE_SOURCE_DIR}"
    -L "${PURE_MODULE_DIR}"
  INPUT_FILE "${TEST_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Pure CSV smoke test exited with ${result}\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_CSV_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "Pure CSV smoke test did not emit its success marker\n${output}${error}")
endif()

message(STATUS "Pure CSV smoke test passed")
