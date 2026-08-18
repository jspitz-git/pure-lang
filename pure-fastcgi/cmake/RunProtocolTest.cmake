foreach(required_variable IN ITEMS
    HARNESS MODULE MODULE_SOURCE WORKER PURE_EXECUTABLE PURE_RUNTIME_DIR TEST_ROOT)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

foreach(required_file IN ITEMS HARNESS MODULE MODULE_SOURCE WORKER PURE_EXECUTABLE)
  if(NOT EXISTS "${${required_file}}")
    message(FATAL_ERROR "${required_file} does not exist: ${${required_file}}")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
get_filename_component(module_name "${MODULE}" NAME)
get_filename_component(module_source_name "${MODULE_SOURCE}" NAME)
get_filename_component(worker_name "${WORKER}" NAME)
file(COPY_FILE "${MODULE}" "${TEST_ROOT}/${module_name}" ONLY_IF_DIFFERENT)
file(COPY_FILE "${MODULE_SOURCE}" "${TEST_ROOT}/${module_source_name}"
  ONLY_IF_DIFFERENT)
file(COPY_FILE "${WORKER}" "${TEST_ROOT}/${worker_name}" ONLY_IF_DIFFERENT)

set(ENV{PATH}
  "${TEST_ROOT};${PURE_RUNTIME_DIR};$ENV{SystemRoot}\\System32;$ENV{SystemRoot};$ENV{SystemRoot}\\System32\\Wbem")
unset(ENV{PURELIB})

execute_process(
  COMMAND "${HARNESS}" "${PURE_EXECUTABLE}" "${TEST_ROOT}"
    "${TEST_ROOT}/${worker_name}"
  RESULT_VARIABLE harness_result
  OUTPUT_VARIABLE harness_output
  ERROR_VARIABLE harness_error
  TIMEOUT 18)
set(harness_log "${harness_output}${harness_error}")
if(NOT harness_result EQUAL 0)
  message(FATAL_ERROR
    "protocol harness failed (result ${harness_result}):\n${harness_log}")
endif()
if(NOT harness_log MATCHES "pure-fastcgi protocol smoke passed")
  message(FATAL_ERROR
    "protocol harness did not emit its success marker:\n${harness_log}")
endif()
message(STATUS "${harness_log}")
