foreach(required IN ITEMS PURE_EXECUTABLE PACKAGE_DIR MODULE_DIR RUNTIME_BIN_DIR
    TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
  cmake_path(ABSOLUTE_PATH ${required} NORMALIZE OUTPUT_VARIABLE normalized)
  set(${required} "${normalized}")
  if(NOT EXISTS "${${required}}")
    message(FATAL_ERROR "${required} does not exist: ${${required}}")
  endif()
endforeach()

cmake_path(GET PURE_EXECUTABLE PARENT_PATH pure_bin)
if(WIN32)
  set(ENV{PATH}
    "${MODULE_DIR};${RUNTIME_BIN_DIR};${pure_bin};C:/Windows/System32;C:/Windows")
  unset(ENV{PURELIB})
  set(run_working_directory "C:/Windows")
else()
  set(ENV{PATH} "${MODULE_DIR}:${RUNTIME_BIN_DIR}:${pure_bin}:$ENV{PATH}")
  set(ENV{LD_LIBRARY_PATH}
    "${MODULE_DIR}:${RUNTIME_BIN_DIR}:$ENV{LD_LIBRARY_PATH}")
  set(ENV{DYLD_LIBRARY_PATH}
    "${MODULE_DIR}:${RUNTIME_BIN_DIR}:$ENV{DYLD_LIBRARY_PATH}")
  set(run_working_directory "${MODULE_DIR}")
endif()

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc
    -I "${PACKAGE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${run_working_directory}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error
  ENCODING UTF-8
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR
    "pure-glpk test failed (${result})\nstdout:\n${output}\nstderr:\n${error}")
endif()
if(NOT error STREQUAL "")
  message(FATAL_ERROR
    "pure-glpk test emitted stderr\nstdout:\n${output}\nstderr:\n${error}")
endif()
message(STATUS "${output}")
