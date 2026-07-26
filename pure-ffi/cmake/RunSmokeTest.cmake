foreach(required_var IN ITEMS
    PURE_EXECUTABLE
    PURE_SOURCE_DIR
    PURE_MODULE_DIR
    NATIVE_MODULE_DIR
    TEST_SCRIPT)
  if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
    message(FATAL_ERROR "${required_var} is required")
  endif()
endforeach()

unset(ENV{PURELIB})

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${PURE_SOURCE_DIR}"
    -L "${PURE_MODULE_DIR}"
    -L "${NATIVE_MODULE_DIR}"
  INPUT_FILE "${TEST_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "Pure FFI smoke test exited with ${result}\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_FFI_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "Pure FFI smoke test did not emit its success marker\n${output}${error}")
endif()

message(STATUS "Pure FFI smoke test passed")
