foreach(required_variable IN ITEMS
    HARNESS MODULE MODULE_SOURCE WORKER HANG_WORKER PURE_EXECUTABLE
    PURE_RUNTIME_DIR TEST_ROOT)
  if(NOT DEFINED ${required_variable} OR "${${required_variable}}" STREQUAL "")
    message(FATAL_ERROR "${required_variable} is required")
  endif()
endforeach()

foreach(required_file IN ITEMS
    HARNESS MODULE MODULE_SOURCE WORKER HANG_WORKER PURE_EXECUTABLE)
  if(NOT EXISTS "${${required_file}}")
    message(FATAL_ERROR "${required_file} does not exist: ${${required_file}}")
  endif()
endforeach()

file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}")
get_filename_component(module_name "${MODULE}" NAME)
get_filename_component(module_source_name "${MODULE_SOURCE}" NAME)
get_filename_component(worker_name "${WORKER}" NAME)
get_filename_component(hang_worker_name "${HANG_WORKER}" NAME)
file(COPY_FILE "${MODULE}" "${TEST_ROOT}/${module_name}" ONLY_IF_DIFFERENT)
file(COPY_FILE "${MODULE_SOURCE}" "${TEST_ROOT}/${module_source_name}"
  ONLY_IF_DIFFERENT)
file(COPY_FILE "${WORKER}" "${TEST_ROOT}/${worker_name}" ONLY_IF_DIFFERENT)
file(COPY_FILE "${HANG_WORKER}" "${TEST_ROOT}/${hang_worker_name}"
  ONLY_IF_DIFFERENT)

set(ENV{PATH}
  "${TEST_ROOT};${PURE_RUNTIME_DIR};$ENV{SystemRoot}\\System32;$ENV{SystemRoot};$ENV{SystemRoot}\\System32\\Wbem")
unset(ENV{PURELIB})

function(expect_failure scenario expected worker)
  string(TIMESTAMP started "%s" UTC)
  execute_process(
    COMMAND "${HARNESS}" "${PURE_EXECUTABLE}" "${TEST_ROOT}"
      "${TEST_ROOT}/${worker}" --scenario "${scenario}"
      --cleanup-report "${TEST_ROOT}/${scenario}.txt"
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err
    TIMEOUT 12)
  string(TIMESTAMP finished "%s" UTC)
  math(EXPR elapsed "${finished} - ${started}")
  if(elapsed GREATER 9)
    message(FATAL_ERROR "${scenario} took ${elapsed} seconds; expected under 10")
  endif()
  if(result EQUAL 0 OR NOT "${out}\n${err}" MATCHES "${expected}")
    message(FATAL_ERROR "${scenario} did not fail as ${expected}:\n${out}\n${err}")
  endif()
  if(NOT EXISTS "${TEST_ROOT}/${scenario}.txt")
    message(FATAL_ERROR "${scenario} did not write a cleanup report")
  endif()
  file(READ "${TEST_ROOT}/${scenario}.txt" cleanup)
  foreach(marker IN ITEMS "child_exited=1" "pipe_closed=1"
      "owned_handles_closed=1")
    if(NOT cleanup MATCHES "${marker}")
      message(FATAL_ERROR "${scenario} cleanup missing ${marker}:\n${cleanup}")
    endif()
  endforeach()
endfunction()

expect_failure(truncated "protocol error while reading PARAMS" "${worker_name}")
expect_failure(timeout "deadline expired while waiting for END_REQUEST"
  "${hang_worker_name}")
