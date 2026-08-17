cmake_minimum_required(VERSION 3.25)

foreach(_required IN ITEMS REDUCE_UPSTREAM_MODULE BASH_EXECUTABLE)
  if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "${_required} is required")
  endif()
endforeach()

string(SHA256 _root_key "${CMAKE_CURRENT_BINARY_DIR}")
file(TO_CMAKE_PATH
  "$ENV{TEMP}/pure reduce run-logged diagnostics-${_root_key}" _root)
file(REMOVE_RECURSE "${_root}")
file(MAKE_DIRECTORY "${_root}")
file(TO_CMAKE_PATH "${REDUCE_UPSTREAM_MODULE}" _module)
file(TO_CMAKE_PATH "${BASH_EXECUTABLE}" _bash)
file(WRITE "${_root}/child.cmake"
  "include(\"${_module}\")\n"
  "_pure_reduce_run_logged(\"diagnostic probe\"\n"
  "  \"${_root}/probe.log\" \"${_bash}\"\n"
  "  \"printf 'run-logged diagnostic marker\\\\n'; exit 17\")\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -P "${_root}/child.cmake"
  RESULT_VARIABLE _result
  OUTPUT_VARIABLE _output
  ERROR_VARIABLE _error
  ENCODING UTF-8)
file(REMOVE_RECURSE "${_root}")

if(_result EQUAL 0)
  message(FATAL_ERROR "failing diagnostic probe unexpectedly succeeded")
endif()
if(NOT "${_output}${_error}" MATCHES "run-logged diagnostic marker")
  message(FATAL_ERROR
    "failed command output was absent from the diagnostic:\n"
    "${_output}${_error}")
endif()
