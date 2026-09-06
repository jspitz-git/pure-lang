foreach(required IN ITEMS PURE_EXECUTABLE PACKAGE_DIR MODULE_DIR
    RUNTIME_BIN_DIR TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
get_filename_component(pure_bin_dir "${PURE_EXECUTABLE}" DIRECTORY)
get_filename_component(pure_prefix "${pure_bin_dir}" DIRECTORY)
if(NOT EXISTS "${pure_prefix}/lib/pure/math.pure")
  message(FATAL_ERROR "PURE_EXECUTABLE must belong to an installed Pure runtime")
endif()
unset(ENV{PURELIB})
if(WIN32)
  foreach(runtime IN ITEMS libgsl-28.dll libgslcblas-0.dll)
    if(NOT EXISTS "${RUNTIME_BIN_DIR}/${runtime}")
      message(FATAL_ERROR "Missing runtime dependency: ${RUNTIME_BIN_DIR}/${runtime}")
    endif()
  endforeach()
  string(CONCAT test_path "${MODULE_DIR};${RUNTIME_BIN_DIR};${pure_bin_dir};"
    "$ENV{SystemRoot}/System32;$ENV{SystemRoot}")
  set(ENV{PATH} "${test_path}")
else()
  set(ENV{PATH} "${MODULE_DIR}:${RUNTIME_BIN_DIR}:${pure_bin_dir}:$ENV{PATH}")
  set(ENV{LD_LIBRARY_PATH}
    "${MODULE_DIR}:${RUNTIME_BIN_DIR}:$ENV{LD_LIBRARY_PATH}")
  set(ENV{DYLD_LIBRARY_PATH}
    "${MODULE_DIR}:${RUNTIME_BIN_DIR}:$ENV{DYLD_LIBRARY_PATH}")
endif()
if(NOT DEFINED RUN_WORKING_DIRECTORY OR RUN_WORKING_DIRECTORY STREQUAL "")
  set(RUN_WORKING_DIRECTORY "${MODULE_DIR}")
endif()
execute_process(COMMAND "${PURE_EXECUTABLE}" --norc
  -I "${PACKAGE_DIR}" -L "${MODULE_DIR}" -x "${TEST_SCRIPT}" run
  WORKING_DIRECTORY "${RUN_WORKING_DIRECTORY}"
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
  ENCODING UTF-8)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-gsl test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "pure-gsl test emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
