foreach(required IN ITEMS
    PURE_EXECUTABLE MODULE_DIR MODULE_DLL_DIR TEST_SCRIPT TEST_ROOT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}/database with spaces žluťoučký")

unset(ENV{PURELIB})
if(WIN32)
  if(NOT DEFINED SQLITE_RUNTIME_DIR OR "${SQLITE_RUNTIME_DIR}" STREQUAL "")
    message(FATAL_ERROR "SQLITE_RUNTIME_DIR is required on Windows")
  endif()
  get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
  get_filename_component(runtime_prefix "${pure_bin_dir}" DIRECTORY)
  if(NOT EXISTS "${runtime_prefix}/lib/pure/math.pure")
    message(FATAL_ERROR
      "PURE_EXECUTABLE must belong to an installed Pure runtime prefix")
  endif()
  set(ENV{PATH}
    "${MODULE_DLL_DIR};${SQLITE_RUNTIME_DIR};${pure_bin_dir};$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
else()
  set(ENV{PATH} "${MODULE_DLL_DIR}:$ENV{PATH}")
endif()
execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -I "${MODULE_DIR}" -x "${TEST_SCRIPT}" "${TEST_ROOT}"
  WORKING_DIRECTORY "${TEST_ROOT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)

file(REMOVE_RECURSE "${TEST_ROOT}")

if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-sql3 smoke test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT "${error}" STREQUAL "")
  message(FATAL_ERROR "pure-sql3 smoke test emitted stderr\n${output}${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_SQL3_SMOKE_OK(\r?\n|$)")
  message(FATAL_ERROR "pure-sql3 smoke test did not emit its success marker")
endif()
message(STATUS "${output}")
