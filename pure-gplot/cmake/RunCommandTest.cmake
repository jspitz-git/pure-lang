foreach(required IN ITEMS
    BUILD_ROOT TEST_ROOT PURE_EXECUTABLE PURE_PREFIX MODULE_DIR MODULE_DLL_DIR TEST_SCRIPT
    GNUPLOT_EXECUTABLE)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()

cmake_path(ABSOLUTE_PATH BUILD_ROOT NORMALIZE OUTPUT_VARIABLE build_root)
cmake_path(ABSOLUTE_PATH TEST_ROOT NORMALIZE OUTPUT_VARIABLE test_root)
cmake_path(IS_PREFIX build_root "${test_root}" NORMALIZE test_is_in_build)
if(NOT test_is_in_build OR test_root STREQUAL build_root)
  message(FATAL_ERROR "TEST_ROOT must be a child of BUILD_ROOT")
endif()
if(NOT EXISTS "${GNUPLOT_EXECUTABLE}")
  message(FATAL_ERROR
    "Controlled gnuplot executable is missing: ${GNUPLOT_EXECUTABLE}")
endif()

file(REMOVE_RECURSE "${test_root}")
file(MAKE_DIRECTORY "${test_root}")
unset(ENV{PURELIB})
set(ENV{GPLOT_EXE} "${GNUPLOT_EXECUTABLE}")
set(ENV{PATH} "${MODULE_DLL_DIR};${PURE_PREFIX}/bin;C:/Windows/System32;C:/Windows")

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${MODULE_DIR}"
    -L "${MODULE_DLL_DIR}"
    -x "${TEST_SCRIPT}"
    "${GNUPLOT_EXECUTABLE}"
  WORKING_DIRECTORY "${test_root}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  TIMEOUT 20
  ENCODING UTF-8)
file(REMOVE_RECURSE "${test_root}")
if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR
    "pure-gplot command test failed (${result})\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT output MATCHES "(^|\r?\n)PURE_GPLOT_COMMAND_OK(\r?\n|$)")
  message(FATAL_ERROR
    "pure-gplot command test did not emit its success marker\n"
    "stdout:\n${output}\nstderr:\n${error}")
endif()
