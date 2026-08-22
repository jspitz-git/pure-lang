foreach(required IN ITEMS
    PURE_EXECUTABLE PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
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
  set(ENV{PATH}
    "${MODULE_DIR};${pure_bin_dir};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
else()
  set(ENV{PATH} "${MODULE_DIR}:$ENV{PATH}")
endif()
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
if(NOT "${error}" STREQUAL "")
  message(FATAL_ERROR
    "pure-stldict smoke emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_STLDICT_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-stldict smoke marker missing\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
