foreach(_required IN ITEMS
    PURE_EXECUTABLE PURE_LIBRARY_DIR PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT
    EXPECTED_MARKER)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

foreach(_path IN ITEMS
    PURE_EXECUTABLE PURE_LIBRARY_DIR PURE_SOURCE_DIR MODULE_DIR TEST_SCRIPT)
  if(NOT EXISTS "${${_path}}")
    message(FATAL_ERROR "${_path} does not exist: ${${_path}}")
  endif()
endforeach()

get_filename_component(_runtime_dir "${PURE_EXECUTABLE}" DIRECTORY)
set(_system_root "$ENV{SystemRoot}")
if(_system_root STREQUAL "")
  set(_system_root "C:/Windows")
endif()
file(TO_CMAKE_PATH "${_system_root}" _system_root)

set(ENV{PATH}
  "${MODULE_DIR};${_runtime_dir};${_system_root}/System32;${_system_root}")
unset(ENV{PURELIB})

execute_process(
  COMMAND "${PURE_EXECUTABLE}" --norc -q
    -I "${PURE_LIBRARY_DIR}"
    -I "${PURE_SOURCE_DIR}"
    -L "${MODULE_DIR}"
    -x "${TEST_SCRIPT}"
  WORKING_DIRECTORY "${_system_root}"
  RESULT_VARIABLE _result
  OUTPUT_VARIABLE _output
  ERROR_VARIABLE _error
  ENCODING UTF-8)

if(NOT _result EQUAL 0)
  message(FATAL_ERROR
    "pure-reduce test exited with ${_result}\n"
    "stdout:\n${_output}\nstderr:\n${_error}")
endif()
if(NOT _error STREQUAL "")
  message(FATAL_ERROR
    "pure-reduce test emitted unexpected stderr\n"
    "stdout:\n${_output}\nstderr:\n${_error}")
endif()
if(NOT _output MATCHES "(^|\r?\n)${EXPECTED_MARKER}(\r?\n|$)")
  message(FATAL_ERROR
    "pure-reduce test did not emit '${EXPECTED_MARKER}'\n"
    "stdout:\n${_output}\nstderr:\n${_error}")
endif()
