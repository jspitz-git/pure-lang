foreach(required_var IN ITEMS
    PURE_EXECUTABLE
    PURE_SOURCE_DIR
    PURE_MODULE_DIR
    TEST_SCRIPT)
  if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
    message(FATAL_ERROR "${required_var} is required")
  endif()
endforeach()

unset(ENV{PURELIB})
if(WIN32)
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
  if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()
  set(ENV{PATH} "${pure_bin_dir};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${PURE_SOURCE_DIR}"
    -L "${PURE_MODULE_DIR}"
  INPUT_FILE "${TEST_SCRIPT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 25
)

if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR
    "Pure sockets loopback test exited with ${result}\n${output}${error}")
endif()
if(NOT "${error}" STREQUAL "")
  message(FATAL_ERROR
    "Pure sockets loopback test emitted stderr\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_SOCKETS_LOOPBACK_OK(\r?\n|$)")
  message(FATAL_ERROR
    "Pure sockets loopback test did not emit its success marker\n"
    "${output}${error}")
endif()

message(STATUS "Pure sockets loopback test passed")
