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
if(WIN32)
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
  get_filename_component(pure_bin_name "${pure_bin_dir}" NAME)
  if(NOT pure_bin_name STREQUAL "bin" OR
      NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()
  set(runtime_path "${pure_bin_dir}")
  if(DEFINED RUNTIME_DLL_DIRECTORY AND NOT RUNTIME_DLL_DIRECTORY STREQUAL "")
    list(APPEND runtime_path "${RUNTIME_DLL_DIRECTORY}")
  endif()
  list(APPEND runtime_path "$ENV{SystemRoot}/System32" "$ENV{SystemRoot}")
  list(JOIN runtime_path ";" sanitized_path)
  set(ENV{PATH} "${sanitized_path}")
  string(TOLOWER "$ENV{PATH}" normalized_path)
  if(normalized_path MATCHES "(^|;).*[/\\\\]msys64[/\\\\]")
    message(FATAL_ERROR "MSYS2 survived Pure FFI PATH sanitization")
  endif()
endif()
if(DEFINED ENV{PURELIB})
  message(FATAL_ERROR "PURELIB survived Pure FFI environment sanitization")
endif()

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
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "Pure FFI smoke test emitted diagnostics\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_FFI_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "Pure FFI smoke test did not emit its success marker\n${output}${error}")
endif()

message(STATUS "Pure FFI smoke test passed")
